--!strict

local Players = game:GetService("Players")

local Manager = require(script.Manager)
local ProfileClass = require(script.ProfileClass)
local Config = require(script.Config)
local Constants = require(script.Constants)
local Network = require(game:GetService("ReplicatedStorage").Shared.Network)
local ValueMirror = require(script.ValueMirror)
local DataProxy = require(script.DataProxy)

type Profile = typeof(ProfileClass.new(nil :: any, nil :: any))
type ProfileStore = { [string]: Profile }

local DataSystem = {}

if not shared._DataSystemProfiles then
	shared._DataSystemProfiles = {} :: ProfileStore
end

local profiles: ProfileStore = shared._DataSystemProfiles

local autoSaveThreads: { [Player]: thread } = {}

local LogLevel = {
	INFO    = "[INFO]",
	SUCCESS = "[✓]",
	WARN    = "[WARN]",
	ERROR   = "[ERROR]",
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

type LoadFailReason = "locked" | "error" | "invalid"

local function attemptLoadProfile(player: Player): (boolean, any?, LoadFailReason?)
	local attempts = 0
	local maxRetries = Constants.SETTING.LoadMaxRetries
	local retryDelay = Constants.SETTING.LoadRetryDelay

	repeat
		local status, result = Manager.UpdateAsync(player, function(data)
			return data
		end)

		if status == "locked" then
			log(LogLevel.WARN, `Session locked for {player.Name}, aborting retries`)
			return false, nil, "locked"
		end

		if status == "ok" and result then
			local valid, err = Config.Validate(result)
			if valid then
				return true, result, nil
			end
			log(LogLevel.WARN, `Invalid data for {player.Name}: {err}`)
			return false, nil, "invalid"
		end

		attempts += 1
		if attempts < maxRetries then
			log(LogLevel.WARN, `Load retry {attempts}/{maxRetries} for {player.Name}`)
			task.wait(retryDelay)
		end
	until attempts >= maxRetries

	return false, nil, "error"
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
	if autoSaveThreads[player] then
		return
	end

	local thread = task.spawn(function()
		while player.Parent and profile:IsActive() do
			task.wait(Constants.SETTING.AutoSaveInterval)

			if not profile:IsActive() then
				break
			end

			local success = Manager.SaveAsync(player, profile.Data)

			if success then
				log(LogLevel.INFO, `Auto-saved profile for {player.Name}`)
			else
				log(LogLevel.ERROR, `Auto-save failed for {player.Name}`)
			end
		end
	end)

	autoSaveThreads[player] = thread
end

local function stopAutoSave(player: Player)
	local thread = autoSaveThreads[player]
	if thread then
		task.cancel(thread)
		autoSaveThreads[player] = nil
	end
end


local function handlePlayerAdded(player: Player)
	local userId = getUserId(player)
	log(LogLevel.INFO, `Loading profile for {player.Name} (ID: {userId})`)

	local success, profileData, failReason = attemptLoadProfile(player)

	if not success or not profileData then
		log(LogLevel.ERROR, `Failed to load profile for {player.Name} (reason: {failReason})`)

		local kickMessages = {
			locked  = "Your session is still active on another server. Please wait 1 minute and try again.",
			invalid = "Your data is corrupt. Please contact support.",
			error   = "Unable to load your data. Try reconnecting.",
		}

		player:Kick(kickMessages[failReason :: string] or "Unknown error loading data.")
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

	local saved = Manager.ReleaseAsync(player, profile.Data)

	if saved then
		log(LogLevel.SUCCESS, `Profile saved and released for {player.Name}`)
	else
		log(LogLevel.ERROR, `Failed to save profile for {player.Name} on leave`)
	end

	profile:Release()
	profiles[userId] = nil
end

function DataSystem:OnStart()
	log(LogLevel.INFO, "Initializing DataSystem...")

	Players.PlayerAdded:Connect(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)

	for _, player in Players:GetPlayers() do
		task.spawn(handlePlayerAdded, player)
	end

	game:BindToClose(function()
		-- On shutdown, save every active profile and release session locks.
		local saveThreads = {}
		for userId, profile in pairs(profiles) do
			local player = Players:GetPlayerByUserId(tonumber(userId))
			if player then
				stopAutoSave(player)
				table.insert(saveThreads, task.spawn(function()
					Manager.ReleaseAsync(player, profile.Data)
					profile:Release()
				end))
			end
		end

		-- Wait for all saves to finish (up to 20s, which is Roblox's BindToClose budget).
		local deadline = os.clock() + 18
		for _, t in saveThreads do
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				break
			end
			task.delay(remaining, function()
				if coroutine.status(t) ~= "dead" then
					task.cancel(t)
				end
			end)
		end

		task.wait(math.clamp(deadline - os.clock(), 0, 18))
	end)

	log(LogLevel.SUCCESS, "DataSystem initialized")
end

function DataSystem:GetProfile(player: Player): Profile?
	if not player then
		return nil
	end

	local userId = getUserId(player)
	local elapsed = 0

	while not profiles[userId] and player.Parent and elapsed < Constants.SETTING.LoadTimeout do
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
		log(LogLevel.ERROR, `Cannot set '{path}': No profile for {player.Name}`)
		return false
	end

	local parent, key = navigateToParent(profile.Data, path)
	if not parent or not key then
		log(LogLevel.ERROR, `Cannot set '{path}': Invalid path`)
		return false
	end

	parent[key] = value
	self:_notifyChange(player, path, value)

	return true
end

function DataSystem:Mutate(player: Player, path: string, mutator: (any) -> any): boolean
	local profile = self:GetProfile(player)
	if not profile then
		log(LogLevel.ERROR, `Cannot mutate '{path}': No profile for {player.Name}`)
		return false
	end

	local value = navigateToValue(profile.Data, path)
	if value == nil then
		log(LogLevel.ERROR, `Cannot mutate '{path}': Path not found`)
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

	if Config.DEBUG_MODE then
		local debugFolder = player:FindFirstChild("_DataDebug")
		if debugFolder then
			ValueMirror.Sync(debugFolder :: Instance, profile.Data)
		end
	end

	Network.FireClient(player, "UpdateState", path, newValue)
end

function DataSystem:Wrap(player: Player)
	local wrapper = {}
	return setmetatable(wrapper, {
		__index = function(_, path: string)
			return DataProxy.new(player, path, self)
		end,
	})
end

return DataSystem
