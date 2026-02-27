--!strict

local DataStoreService = game:GetService("DataStoreService")
local Constants = require(script.Parent.Constants)

local Manager = {}

local dataStore = DataStoreService:GetDataStore("GameData_V1")

local function log(level: string, message: string)
	local timestamp = os.date("%H:%M:%S")
	print(`{timestamp} [Manager]{level} {message}`)
end

local function deepClone(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepClone(v)
	end
	return copy
end

function Manager.UpdateAsync(player: Player, transformFunc: (any) -> any?): (boolean, any?)
	local key = `Player_{player.UserId}`

	local success, result = pcall(function()
		return dataStore:UpdateAsync(key, function(oldData)
			oldData = oldData or table.clone(Constants.STRUCTURE)

			if type(oldData.MetaData) ~= "table" then
				oldData.MetaData = table.clone(Constants.STRUCTURE.MetaData)
			end

			local meta = oldData.MetaData

			if meta.ActiveSession and meta.ActiveSession ~= game.JobId then
				local timeSinceLastSave = os.time() - (meta._last_save or 0)

				if timeSinceLastSave < Constants.SETTING.SessionLockTimeout then
					log("[WARN]", `Session locked for {player.Name} (last save {timeSinceLastSave}s ago)`)
					return nil 
				end

				log("[WARN]", `Stealing stale session lock for {player.Name}`)
			end

			meta.ActiveSession = game.JobId
			meta._last_save = os.time()
			meta.SessionLoadCount += 1

			return transformFunc(oldData)
		end)
	end)

	if not success then
		log("[ERROR]", `UpdateAsync failed for {player.Name}: {result}`)
		return false, nil
	end

	return true, result
end

function Manager.SaveAsync(player: Player, profileData: any): boolean
	local key = `Player_{player.UserId}`

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(oldData)
			if not oldData then
				return nil -- nothing to update; profile was never written
			end
			oldData.Data = deepClone(profileData)
			oldData.MetaData._last_save = os.time()
			return oldData
		end)
	end)

	if not success then
		log("[ERROR]", `SaveAsync failed for {player.Name}: {err}`)
		return false
	end

	return true
end

function Manager.ReleaseAsync(player: Player, profileData: any): boolean
	local key = `Player_{player.UserId}`

	local success, err = pcall(function()
		dataStore:UpdateAsync(key, function(oldData)
			if not oldData then
				return nil
			end

			oldData.Data = deepClone(profileData)
			oldData.MetaData.ActiveSession = nil
			oldData.MetaData._last_save = os.time()
			return oldData
		end)
	end)

	if not success then
		log("[ERROR]", `ReleaseAsync failed for {player.Name}: {err}`)
		return false
	end

	return true
end

function Manager.WipeDataAsync(userId: number): boolean
	local key = `Player_{userId}`

	local success, err = pcall(function()
		dataStore:RemoveAsync(key)
	end)

	if not success then
		log("[ERROR]", `Failed to wipe data for UserId {userId}: {err}`)
		return false
	end

	log("[INFO]", `Data wiped for UserId {userId}`)
	return true
end

return Manager
