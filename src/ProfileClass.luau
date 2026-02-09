--!strict
local ProfileClass = {}
ProfileClass.__index = ProfileClass

type Callback = (data: any) -> ()

function ProfileClass.new(player: Player, rawData: any)
    local self = setmetatable({
        Data = rawData.Data,
        MetaData = rawData.MetaData,
        GlobalUpdates = rawData.GlobalUpdates, 
        
        Player = player,
        _is_released = false,
        
        _release_listeners = {} :: {Callback},
        _meta_data_listeners = {} :: {Callback},
        _hop_ready_listeners = {} :: {Callback},
    }, ProfileClass)
    
    return self
end

function ProfileClass:AddUserId(userId: number)
    if not table.find(self.MetaData.UserIds, userId) then
        table.insert(self.MetaData.UserIds, userId)
    end
end

function ProfileClass:GetGlobalUpdates()
    return self.GlobalUpdates
end

function ProfileClass:IsActive(): boolean
    return not self._is_released and self.Player.Parent ~= nil
end

function ProfileClass:ListenToRelease(callback: Callback)
    if self._is_released then
        task.spawn(callback, self.Data)
        return
    end
    table.insert(self._release_listeners, callback)
end

function ProfileClass:ListenToHopReady(callback: Callback)
    table.insert(self._hop_ready_listeners, callback)
end

function ProfileClass:Release()
    if self._is_released then return end
    self._is_released = true
    
    for _, cb in ipairs(self._release_listeners) do
        task.spawn(cb, self.Data)
    end
end

function ProfileClass:Reconcile(template: any)
    local function reconcileTable(target, temp)
        for key, value in pairs(temp) do
            if target[key] == nil then
                if typeof(value) == "table" then
                    target[key] = table.clone(value)
                    reconcileTable(target[key], value)
                else
                    target[key] = value
                end
            elseif typeof(target[key]) == "table" and typeof(value) == "table" then
                reconcileTable(target[key], value)
            end
        end
    end
    reconcileTable(self.Data, template)
end

function ProfileClass:ClearMetaDataListeners()
    self._meta_data_listeners = {}
end

return ProfileClass
