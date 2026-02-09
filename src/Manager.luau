--!strict

local DataStoreService = game:GetService("DataStoreService")
local Constants = require(script.Parent.Constants)

local Manager = {}

local dataStore = DataStoreService:GetDataStore("GameData_V1")

local function log(level: string, message: string)
	local timestamp = os.date("%H:%M:%S")
	print(`{timestamp} [Manager]{level} {message}`)
end

function Manager.UpdateAsync(player: Player, transformFunc: (any) -> any): (boolean, any?)
	local key = `Player_{player.UserId}`
	
	local success, result = pcall(function()
		return dataStore:UpdateAsync(key, function(oldData)
			oldData = oldData or table.clone(Constants.STRUCTURE)
			
			local meta = oldData.MetaData
			
			if meta.ActiveSession and meta.ActiveSession ~= game.JobId then
				local timeSinceLastPing = os.clock() - (meta._last_ping or 0)
				
				if timeSinceLastPing < Constants.SETTING.SessionLockTimeout then
					log("[WARN]", `Session locked for {player.Name}`)
					return nil 
				end
			end
			
			meta.ActiveSession = game.JobId
			meta._last_ping = os.clock()
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
