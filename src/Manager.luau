--!strict
local DataStoreService = game:GetService("DataStoreService")
local Constants        = require(script.Parent.Constants)

local Manager = {}
local dataStore = DataStoreService:GetDataStore("GameData_V1")

-- Threads de ping ativos por userId
local _pingThreads: {[string]: thread} = {}

local PING_INTERVAL        = 60   -- segundos entre pings
local SESSION_LOCK_TIMEOUT = 120  -- segundos sem ping = sessão morta

------------------------------------------------------------------------
-- UTILITÁRIOS
------------------------------------------------------------------------

local function log(level: string, message: string)
	print(`{os.date("%H:%M:%S")} [Manager]{level} {message}`)
end

local function deepClone(t: any): any
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepClone(v)
	end
	return copy
end

local function resolveKey(player: Player | number): string
	if typeof(player) == "Instance" and (player :: any):IsA("Player") then
		return `Player_{(player :: Player).UserId}`
	end
	return `Player_{tostring(player)}`
end

local function resolveUserId(player: Player | number): string
	if typeof(player) == "Instance" and (player :: any):IsA("Player") then
		return tostring((player :: Player).UserId)
	end
	return tostring(player)
end

------------------------------------------------------------------------
-- SISTEMA DE PING
-- Mantém _last_ping atualizado enquanto o servidor está vivo.
-- Se o servidor travar, o ping para e o lock expira em SESSION_LOCK_TIMEOUT.
------------------------------------------------------------------------

local function doPing(key: string)
	pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			if not old or not old.MetaData then return nil end
			if old.MetaData.ActiveSession ~= game.JobId then return nil end
			old.MetaData._last_ping = os.time()
			return old
		end)
	end)
end

-- Inicia loop de ping. Chamar após load bem-sucedido.
function Manager.StartPing(player: Player | number)
	local userId = resolveUserId(player)
	local key    = resolveKey(player)

	Manager.StopPing(player)

	_pingThreads[userId] = task.spawn(function()
		while _pingThreads[userId] do
			task.wait(PING_INTERVAL)
			if not _pingThreads[userId] then break end
			doPing(key)
		end
	end)
end

-- Para o loop de ping. Chamar antes do save final.
function Manager.StopPing(player: Player | number)
	local userId = resolveUserId(player)
	local thread = _pingThreads[userId]
	if thread then
		task.cancel(thread)
		_pingThreads[userId] = nil
	end
end

------------------------------------------------------------------------
-- UPDATE ASYNC
-- Lê, verifica session lock e transforma os dados.
-- Retorna (success: boolean, result: any)
--
-- Session lock:
--   Bloqueado se outro JobId ativo E _last_ping recente (< SESSION_LOCK_TIMEOUT).
--   Se ping parou (servidor travado), lock expira automaticamente em ~120s.
--   Ao sair normalmente, ReleaseAsync zera ActiveSession → próximo load imediato.
------------------------------------------------------------------------

function Manager.UpdateAsync(player: Player | number, transformFunc: (any) -> any): (boolean, any?)
	local key = resolveKey(player)

	local success, result = pcall(function()
		return dataStore:UpdateAsync(key, function(old: any)
			old = old or deepClone(Constants.STRUCTURE)

			if type(old.MetaData) ~= "table" then
				old.MetaData = deepClone(Constants.STRUCTURE.MetaData)
			end

			local meta    = old.MetaData
			local elapsed = os.time() - (meta._last_ping or 0)

			if meta.ActiveSession and meta.ActiveSession ~= game.JobId then
				if elapsed < SESSION_LOCK_TIMEOUT then
					local remaining = SESSION_LOCK_TIMEOUT - elapsed
					log("[WARN]", `Session lock ativo: "{key}" — expira em {remaining}s`)
					return nil -- DataStore não salva, caller recebe nil
				end
				log("[WARN]", `Session lock expirado: "{key}" — assumindo sessão após {elapsed}s`)
			end

			meta.ActiveSession    = game.JobId
			meta._last_ping       = os.time()
			meta.SessionLoadCount = (meta.SessionLoadCount or 0) + 1

			-- Deep clone garante que transformFunc nunca recebe referências internas
			return transformFunc(deepClone(old))
		end)
	end)

	if not success then
		log("[ERROR]", `UpdateAsync falhou: {result}`)
		return false, nil
	end

	return true, result
end

------------------------------------------------------------------------
-- SAVE ASYNC
-- Salva dados sem liberar a sessão (usado pelo auto-save).
-- Usa snapshot para evitar referências vivas no callback.
------------------------------------------------------------------------

function Manager.SaveAsync(player: Player | number, profileData: any): boolean
	local key      = resolveKey(player)
	local snapshot = deepClone(profileData) -- captura ANTES do pcall

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			if not old then return nil end
			-- Verifica se ainda somos donos da sessão antes de salvar
			if old.MetaData and old.MetaData.ActiveSession ~= game.JobId then
				log("[WARN]", `SaveAsync abortado: sessão de "{key}" pertence a outro servidor`)
				return nil
			end
			old.Data              = snapshot
			old.MetaData._last_ping = os.time()
			return old
		end)
	end)

	if not success then
		log("[ERROR]", `SaveAsync falhou: {err}`)
		return false
	end

	return true
end

------------------------------------------------------------------------
-- RELEASE ASYNC
-- Salva dados e libera o session lock.
-- Chamar ao sair (PlayerRemoving / BindToClose).
------------------------------------------------------------------------

function Manager.ReleaseAsync(player: Player | number, profileData: any): boolean
	local key      = resolveKey(player)
	local snapshot = deepClone(profileData) -- captura ANTES do pcall

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			if not old then return nil end
			old.Data                    = snapshot
			old.MetaData.ActiveSession  = nil  -- libera o lock imediatamente
			old.MetaData._last_ping     = 0
			return old
		end)
	end)

	if not success then
		log("[ERROR]", `ReleaseAsync falhou: {err}`)
		return false
	end

	return true
end

------------------------------------------------------------------------
-- WIPE
------------------------------------------------------------------------

function Manager.WipeDataAsync(userId: number): boolean
	Manager.StopPing(userId)
	local key = `Player_{userId}`

	local success, err = pcall(function()
		dataStore:RemoveAsync(key)
	end)

	if not success then
		log("[ERROR]", `WipeDataAsync falhou para UserId {userId}: {err}`)
		return false
	end

	log("[INFO]", `Dados removidos para UserId {userId}`)
	return true
end

return Manager
