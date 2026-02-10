--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Manager = require(script.Manager)
local ProfileClass = require(script.ProfileClass)
local Config = require(script.Config)
local Network = require(ReplicatedStorage.Shared.Network)
local ValueMirror = require(script.ValueMirror)

type Profile = typeof(ProfileClass.new(nil :: any, nil :: any))
type ProfileStore = { [string]: Profile }

local DataSystem = {}

local LOAD_TIMEOUT = 10
local LOAD_RETRY_DELAY = 2
local MAX_LOAD_RETRIES = 5

if not shared._DataSystemProfiles then
	shared._DataSystemProfiles = {} :: ProfileStore
end

local profiles: ProfileStore = shared._DataSystemProfiles
local autoSaveTasks: { [Player]: thread } = {}

local LogLevel = {
	INFO = "[INFO]",
	SUCCESS = "[✓]",
	WARN = "[WARN]",
	ERROR = "[ERROR]",
}

local function log(level: string, message: string)
	local timestamp = os.date("%H:%M:%S")
	print(`{timestamp} [DataSystem]{level} {message}`)
end

local function getUserId(player: Player): string
	return tostring(player.UserId)
end

local function splitPath(path: string): { string }
	return path:split(".")
end

local function navigateToValue(data: any, path: string): any?
	local keys = splitPath(path)
	local current = data

	for _, key in keys do
		if type(current) ~= "table" or current[key] == nil then
			return nil
		end
		current = current[key]
	end

	return current
end

local function navigateToParent(data: any, path: string): (any?, string?)
	local keys = splitPath(path)
	local current = data

	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(current) ~= "table" or current[key] == nil then
			return nil, nil
		end
		current = current[key]
	end

	return current, keys[#keys]
end

local function attemptLoadProfile(player: Player): (boolean, any?)
	local attempts = 0

	repeat
		local success, result = Manager.UpdateAsync(player, function(data)
			return data
		end)

		if success and result then
			return true, result
		end

		attempts += 1
		if attempts < MAX_LOAD_RETRIES then
			log(LogLevel.WARN, `Load retry {attempts}/{MAX_LOAD_RETRIES} for {player.Name}`)
			task.wait(LOAD_RETRY_DELAY)
		end
	until attempts >= MAX_LOAD_RETRIES

	return false, nil
end

local function setupDebugVisualization(player: Player, profileData: any)
	if not Config.DEBUG_MODE then
		return
	end

	local folder = player:FindFirstChild("_DataDebug") or Instance.new("Folder")
	folder.Name = "_DataDebug"
	folder.Parent = player

	ValueMirror.Sync(folder, profileData)
end

local function startAutoSave(player: Player, profile: Profile)
	if autoSaveTasks[player] then
		return
	end

	local task = task.spawn(function()
		while player.Parent and profile:IsActive() do
			task.wait(Config.AUTO_SAVE_INTERVAL)

			if not profile:IsActive() then
				break
			end

			local success = Manager.UpdateAsync(player, function(old)
				if not old then
					return nil
				end
				old.Data = profile.Data
				return old
			end)

			if success then
				log(LogLevel.INFO, `Auto-saved profile for {player.Name}`)
			else
				log(LogLevel.ERROR, `Auto-save failed for {player.Name}`)
			end
		end
	end)

	autoSaveTasks[player] = task
end

local function stopAutoSave(player: Player)
	local taskThread = autoSaveTasks[player]
	if taskThread then
		task.cancel(taskThread)
		autoSaveTasks[player] = nil
	end
end

local function handlePlayerAdded(player: Player)
	local userId = getUserId(player)
	log(LogLevel.INFO, `Loading profile for {player.Name} (ID: {userId})`)

	local success, profileData = attemptLoadProfile(player)

	if not success or not profileData then
		log(LogLevel.ERROR, `Failed to load profile for {player.Name} after {MAX_LOAD_RETRIES} attempts`)
		player:Kick("Failed to load your data. Please try rejoining.")
		return
	end

	local profile = ProfileClass.new(player, profileData)
	profile:Reconcile(Config.TEMPLATE)

	profiles[userId] = profile

	setupDebugVisualization(player, profile.Data)

	startAutoSave(player, profile)

	Network.FireClient(player, "UpdateState", "All", profile.Data)

	log(LogLevel.SUCCESS, `Profile loaded for {player.Name}`)
end

local function handlePlayerRemoving(player: Player)
	local userId = getUserId(player)
	local profile = profiles[userId]

	if not profile then
		return
	end

	stopAutoSave(player)

	local success = Manager.UpdateAsync(player, function(old)
		if not old then
			return nil
		end
		old.Data = profile.Data
		profile:Release()
		return old
	end)

	if success then
		log(LogLevel.SUCCESS, `Profile saved and released for {player.Name}`)
	else
		log(LogLevel.ERROR, `Failed to save profile for {player.Name}`)
	end

	profiles[userId] = nil
end

function DataSystem:OnStart()
	log(LogLevel.INFO, "Initializing DataSystem...")

	Players.PlayerAdded:Connect(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(handlePlayerAdded, player)
	end

	log(LogLevel.SUCCESS, "DataSystem initialized")
end

function DataSystem:GetProfile(player: Player): Profile?
	if not player then
		return nil
	end

	local userId = getUserId(player)
	local elapsed = 0

	while not profiles[userId] and player.Parent and elapsed < LOAD_TIMEOUT do
		elapsed += task.wait(0.1)
	end

	local profile = profiles[userId]

	if not profile then
		log(LogLevel.WARN, `Profile timeout for {player.Name}`)
	end

	return profile
end

function DataSystem:Get(player: Player, path: string): any?
	local profile = self:GetProfile(player)
	if not profile then
		return nil
	end

	return navigateToValue(profile.Data, path)
end

function DataSystem:Set(player: Player, path: string, value: any): boolean
	local profile = self:GetProfile(player)
	if not profile then
		log(LogLevel.ERROR, `Cannot set {path}: No profile for {player.Name}`)
		return false
	end

	local parent, key = navigateToParent(profile.Data, path)
	if not parent or not key then
		log(LogLevel.ERROR, `Invalid path: {path}`)
		return false
	end

	parent[key] = value
	self:_notifyChange(player, path, value)

	return true
end

function DataSystem:Mutate(player: Player, path: string, mutator: (any) -> any): boolean
	local profile = self:GetProfile(player)
	if not profile then
		log(LogLevel.ERROR, `Cannot mutate {path}: No profile for {player.Name}`)
		return false
	end

	local value = navigateToValue(profile.Data, path)
	if value == nil then
		log(LogLevel.ERROR, `Invalid path: {path}`)
		return false
	end

	local newValue = mutator(value)
	return self:Set(player, path, newValue)
end

function DataSystem:_notifyChange(player: Player, path: string, newValue: any)
	local userId = getUserId(player)
	local profile = profiles[userId]

	if not profile then
		return
	end

	-- Update debug visualization
	if Config.DEBUG_MODE then
		local debugFolder = player:FindFirstChild("_DataDebug")
		if debugFolder then
			ValueMirror.Sync(debugFolder, profile.Data)
		end
	end

	-- Notify client
	Network.FireClient(player, "UpdateState", path, newValue)
end

return DataSystem
