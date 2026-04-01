--!strict
local Players = game:GetService("Players")

local Manager      = require(script.Manager)
local ProfileClass = require(script.ProfileClass)
local Config       = require(script.Config)
local Constants    = require(script.Constants)
local Network      = require(game:GetService("ReplicatedStorage").Shared.Network)
local ValueMirror  = require(script.ValueMirror)
local DataProxy    = require(script.DataProxy)

type Profile      = typeof(ProfileClass.new(nil :: any, nil :: any))
type ProfileStore = { [string]: Profile }

------------------------------------------------------------------------

local DataSystem = {}

-- shared persiste entre re-requires do mesmo servidor (hot-reload no Studio)
if not shared._KoreghProfiles then
	shared._KoreghProfiles = {} :: ProfileStore
end

local profiles: ProfileStore      = shared._KoreghProfiles
local autoSaveThreads: { [Player]: thread } = {}

------------------------------------------------------------------------
-- LOGGING
------------------------------------------------------------------------

local LogLevel = {
	INFO    = "[INFO]",
	SUCCESS = "[✓]",
	WARN    = "[WARN]",
	ERROR   = "[ERROR]",
}

local function log(level: string, message: string)
	print(`{os.date("%H:%M:%S")} [DataSystem]{level} {message}`)
end

------------------------------------------------------------------------
-- UTILITÁRIOS
------------------------------------------------------------------------

local function getUserId(player: Player): string
	return tostring(player.UserId)
end

local function navigateToValue(data: any, path: string): any?
	local keys    = path:split(".")
	local current = data
	for _, key in ipairs(keys) do
		if type(current) ~= "table" or current[key] == nil then return nil end
		current = current[key]
	end
	return current
end

local function navigateToParent(data: any, path: string): (any?, string?)
	local keys    = path:split(".")
	local current = data
	for i = 1, #keys - 1 do
		local key = keys[i]
		if type(current) ~= "table" or current[key] == nil then return nil, nil end
		current = current[key]
	end
	return current, keys[#keys]
end

------------------------------------------------------------------------
-- LOAD
-- Tenta carregar o perfil com retries.
-- Retorna (success, data, failReason).
-- failReason: "locked" | "invalid" | "error"
------------------------------------------------------------------------

type FailReason = "locked" | "invalid" | "error"

local function attemptLoadProfile(player: Player): (boolean, any?, FailReason?)
	local attempts  = 0
	local maxRetries = Constants.SETTING.LoadMaxRetries
	local retryDelay = Constants.SETTING.LoadRetryDelay

	repeat
		local ok, result = Manager.UpdateAsync(player, function(data) return data end)

		if ok and result == nil then
			-- result nil = session lock ativo, sem sentido em tentar de novo agora
			log(LogLevel.WARN, `Session lock ativo para {player.Name}, abortando`)
			return false, nil, "locked"
		end

		if ok and result then
			local valid, err = Config.Validate(result)
			if valid then
				return true, result, nil
			end
			log(LogLevel.WARN, `Dados inválidos para {player.Name}: {err}`)
			return false, nil, "invalid"
		end

		attempts += 1
		if attempts < maxRetries then
			log(LogLevel.WARN, `Retry {attempts}/{maxRetries} para {player.Name}`)
			task.wait(retryDelay)
		end
	until attempts >= maxRetries

	return false, nil, "error"
end

------------------------------------------------------------------------
-- DEBUG MIRROR
------------------------------------------------------------------------

local function setupDebugVisualization(player: Player, data: any)
	if not Config.DEBUG_MODE then return end

	local folder = player:FindFirstChild("_DataDebug") or Instance.new("Folder")
	folder.Name   = "_DataDebug"
	folder.Parent = player
	ValueMirror.Sync(folder, data)
end

------------------------------------------------------------------------
-- AUTO-SAVE
------------------------------------------------------------------------

local function startAutoSave(player: Player, profile: Profile)
	if autoSaveThreads[player] then return end

	autoSaveThreads[player] = task.spawn(function()
		while player.Parent and profile:IsActive() do
			task.wait(Constants.SETTING.AutoSaveInterval)
			if not profile:IsActive() then break end

			local saved = Manager.SaveAsync(player, profile.Data)
			if saved then
				log(LogLevel.INFO, `Auto-save ok: {player.Name}`)
			else
				log(LogLevel.ERROR, `Auto-save falhou: {player.Name}`)
			end
		end
	end)
end

local function stopAutoSave(player: Player)
	local thread = autoSaveThreads[player]
	if thread then
		task.cancel(thread)
		autoSaveThreads[player] = nil
	end
end

------------------------------------------------------------------------
-- PLAYER ADDED
------------------------------------------------------------------------

local function handlePlayerAdded(player: Player)
	local userId = getUserId(player)
	log(LogLevel.INFO, `Carregando perfil: {player.Name} ({userId})`)

	local success, profileData, failReason = attemptLoadProfile(player)

	-- Verifica se o player ainda está no jogo após os retries
	if not player.Parent then return end

	if not success or not profileData then
		local kickMessages = {
			locked  = "Sua sessão ainda está ativa em outro servidor. Aguarde 2 minutos e tente novamente.",
			invalid = "Seus dados estão corrompidos. Entre em contato com o suporte.",
			error   = "Não foi possível carregar seus dados. Tente reconectar.",
		}
		player:Kick(kickMessages[failReason :: string] or "Erro desconhecido ao carregar dados.")
		log(LogLevel.ERROR, `Falha ao carregar {player.Name}: {failReason}`)
		return
	end

	local profile = ProfileClass.new(player, profileData)
	profile:Reconcile(Config.TEMPLATE)

	profiles[userId] = profile

	setupDebugVisualization(player, profile.Data)
	startAutoSave(player, profile)
	Manager.StartPing(player) -- mantém o session lock vivo

	Network.FireClient(player, "UpdateState", "All", profile.Data)
	log(LogLevel.SUCCESS, `Perfil carregado: {player.Name}`)
end

------------------------------------------------------------------------
-- PLAYER REMOVING
------------------------------------------------------------------------

local function handlePlayerRemoving(player: Player)
	local userId  = getUserId(player)
	local profile = profiles[userId]
	if not profile then return end

	stopAutoSave(player)
	Manager.StopPing(player) -- para o ping antes de liberar

	local saved = Manager.ReleaseAsync(player, profile.Data)
	if saved then
		log(LogLevel.SUCCESS, `Perfil salvo e liberado: {player.Name}`)
	else
		log(LogLevel.ERROR, `Falha ao salvar perfil de {player.Name} ao sair`)
	end

	profile:Release()
	profiles[userId] = nil
end

------------------------------------------------------------------------
-- ON START
------------------------------------------------------------------------

function DataSystem:OnStart()
	log(LogLevel.INFO, "Inicializando DataSystem...")

	Players.PlayerAdded:Connect(handlePlayerAdded)
	Players.PlayerRemoving:Connect(handlePlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(handlePlayerAdded, player)
	end

	-- Salva todos ao fechar e aguarda cada save terminar de verdade
	game:BindToClose(function()
		local threads = {}

		for userId, profile in pairs(profiles) do
			local player = Players:GetPlayerByUserId(tonumber(userId))
			if not player then continue end

			stopAutoSave(player)
			Manager.StopPing(player)

			table.insert(threads, task.spawn(function()
				local ok, err = pcall(function()
					Manager.ReleaseAsync(player, profile.Data)
					profile:Release()
				end)
				if not ok then
					log(LogLevel.ERROR, `Erro ao salvar {userId} no fechamento: {err}`)
				end
			end))
		end

		-- Aguarda todos terminarem (Roblox dá ~30s de budget no BindToClose)
		for _, thread in ipairs(threads) do
			while coroutine.status(thread) ~= "dead" do
				task.wait()
			end
		end
	end)

	log(LogLevel.SUCCESS, "DataSystem inicializado")
end

------------------------------------------------------------------------
-- GET PROFILE
------------------------------------------------------------------------

function DataSystem:GetProfile(player: Player): Profile?
	if not player then return nil end

	local userId  = getUserId(player)
	local elapsed = 0

	while not profiles[userId] do
		if not player.Parent then return nil end
		if elapsed >= Constants.SETTING.LoadTimeout then
			log(LogLevel.WARN, `Timeout aguardando perfil de {player.Name}`)
			return nil
		end
		elapsed += task.wait(0.1)
	end

	return profiles[userId]
end

------------------------------------------------------------------------
-- GET / SET / MUTATE
------------------------------------------------------------------------

function DataSystem:Get(player: Player, path: string): any?
	local profile = self:GetProfile(player)
	if not profile then return nil end
	return navigateToValue(profile.Data, path)
end

function DataSystem:Set(player: Player, path: string, value: any): boolean
	local profile = self:GetProfile(player)
	if not profile then
		log(LogLevel.ERROR, `Set "{path}" falhou: sem perfil para {player.Name}`)
		return false
	end

	local parent, key = navigateToParent(profile.Data, path)
	if not parent or not key then
		log(LogLevel.ERROR, `Set "{path}" falhou: caminho inválido`)
		return false
	end

	parent[key] = value
	self:_notifyChange(player, path, value)
	return true
end

function DataSystem:Mutate(player: Player, path: string, mutator: (any) -> any): boolean
	local profile = self:GetProfile(player)
	if not profile then
		log(LogLevel.ERROR, `Mutate "{path}" falhou: sem perfil para {player.Name}`)
		return false
	end

	local value = navigateToValue(profile.Data, path)
	if value == nil then
		log(LogLevel.ERROR, `Mutate "{path}" falhou: caminho não encontrado`)
		return false
	end

	return self:Set(player, path, mutator(value))
end

------------------------------------------------------------------------
-- NOTIFY CHANGE
------------------------------------------------------------------------

function DataSystem:_notifyChange(player: Player, path: string, newValue: any)
	local profile = profiles[getUserId(player)]
	if not profile then return end

	if Config.DEBUG_MODE then
		local folder = player:FindFirstChild("_DataDebug")
		if folder then
			ValueMirror.Sync(folder :: Instance, profile.Data)
		end
	end

	Network.FireClient(player, "UpdateState", path, newValue)
end

------------------------------------------------------------------------
-- WRAP (DataProxy)
------------------------------------------------------------------------

function DataSystem:Wrap(player: Player)
	return setmetatable({}, {
		__index = function(_, path: string)
			return DataProxy.new(player, path, self)
		end,
	})
end

return DataSystem
