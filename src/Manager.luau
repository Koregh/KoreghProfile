--!strict
local DataStoreService = game:GetService("DataStoreService")
local Constants        = require(script.Parent.Constants)

local Manager = {}
local dataStore = DataStoreService:GetDataStore("GameData_V1")

-- Threads de ping ativos por userId
local _pingThreads: {[string]: thread} = {}

local PING_INTERVAL = 60 -- seconds between pings
local SESSION_LOCK_TIMEOUT = 120 -- seconds without ping = dead session


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

-- Start ping loop. Call after successful load.
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

-- Stops the ping loop. Call before final save.
function Manager.StopPing(player: Player | number)
	local userId = resolveUserId(player)
	local thread = _pingThreads[userId]
	if thread then
		task.cancel(thread)
		_pingThreads[userId] = nil
	end
end

-- UPDATE ASYNC!!!!!!!
-- Reads, checks session lock and transforms the data.
-- Returns (success: boolean, result: any)
--
-- Session lock:
-- Blocked if other active JobId AND recent _last_ping (< SESSION_LOCK_TIMEOUT).
-- If ping stopped (server locked), lock automatically expires in ~120s.
-- When exiting normally, ReleaseAsync resets ActiveSession → next load immediately.

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
					log("[WARN]", `Session lock active: "{key}" — expires in {remaining}s`)
					return nil -- DataStore does not save, caller receives nil
				end
				log("[WARN]", `Session lock expired: "{key}" — assuming session after {elapsed}s`)
			end

			meta.ActiveSession    = game.JobId
			meta._last_ping       = os.time()
			meta.SessionLoadCount = (meta.SessionLoadCount or 0) + 1

			-- Deep clone ensures that transformFunc never receives internal references
			return transformFunc(deepClone(old))
		end)
	end)

	if not success then
		log("[ERROR]", `UpdateAsync falhou: {result}`)
		return false, nil
	end

	return true, result
end

function Manager.SaveAsync(player: Player | number, profileData: any): boolean
	local key      = resolveKey(player)
	local snapshot = deepClone(profileData) -- captura ANTES do pcall

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			if not old then return nil end
			-- Check if we still own the session before saving
			if old.MetaData and old.MetaData.ActiveSession ~= game.JobId then
				log("[WARN]", `SaveAsync aborted: session of "{key}" belongs to another server`)
				return nil
			end
			old.Data              = snapshot
			old.MetaData._last_ping = os.time()
			return old
		end)
	end)

	if not success then
	log("[ERROR]", `SaveAsync failed: {err}`)
		return false
	end

	return true
end



function Manager.ReleaseAsync(player: Player | number, profileData: any): boolean
	local key      = resolveKey(player)
	local snapshot = deepClone(profileData) 

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(old: any)
			if not old then return nil end
			old.Data                    = snapshot
			old.MetaData.ActiveSession  = nil  -
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


function Manager.WipeDataAsync(userId: number): boolean
	Manager.StopPing(userId)
	local key = `Player_{userId}`

	local success, err = pcall(function()
		dataStore:RemoveAsync(key)
	end)

	if not success then
	log("[ERROR]", `WipeDataAsync failed for UserId {userId}: {err}`)
		return false
	end

	log("[INFO]", `Data removed for UserId {userId}`)
	return true
end

return Manager
