--!strict
local DataStoreService = game:GetService("DataStoreService")
local Constants = require(script.Parent.Constants)

local Manager = {}
local _store = DataStoreService:GetDataStore("GameData_V1")

function Manager.UpdateAsync(player: Player, transformFunc: (any) -> any)
    local key = "Player_" .. player.UserId
    local success, result = pcall(function()
        return _store:UpdateAsync(key, function(old)
            old = old or table.clone(Constants.STRUCTURE)
            
            local meta = old.MetaData
            if meta.ActiveSession ~= nil and meta.ActiveSession ~= game.JobId then
                if os.clock() - (meta._last_ping or 0) < Constants.SETTING.SessionLockTimeout then
                    return nil 
                end
            end
            
            meta.ActiveSession = game.JobId
            meta._last_ping = os.clock()
            meta.SessionLoadCount += 1
            
            return transformFunc(old)
        end)
    end)
    return success, result
end


function Manager.WipeDataAsync(userId: number)
    local key = "Player_" .. userId
    local success, err = pcall(function()
        _store:RemoveAsync(key)
    end)
    
    if not success then
        warn(`[Manager] Erro ao deletar dados do UserId {userId}: {err}`)
    end
    
    return success
end

return Manager
