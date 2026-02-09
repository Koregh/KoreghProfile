--!strict

export type Callback = (data: any) -> ()

export type Profile = {
	Data: { [string]: any },
	MetaData: {
		ProfileCreateTime: number,
		SessionLoadCount: number,
		ActiveSession: string?,
		ForceLoadSteps: number,
		UserIds: { number },
		_last_ping: number?,
	},
	GlobalUpdates: any,
	Player: Player,
	
	_is_released: boolean,
	_release_listeners: { Callback },
	_meta_data_listeners: { Callback },
	_hop_ready_listeners: { Callback },
	
	AddUserId: (self: Profile, userId: number) -> (),
	GetGlobalUpdates: (self: Profile) -> any,
	IsActive: (self: Profile) -> boolean,
	ListenToRelease: (self: Profile, callback: Callback) -> (),
	ListenToHopReady: (self: Profile, callback: Callback) -> (),
	Release: (self: Profile) -> (),
	Reconcile: (self: Profile, template: any) -> (),
	ClearMetaDataListeners: (self: Profile) -> (),
}

local ProfileClass = {}
ProfileClass.__index = ProfileClass

function ProfileClass.new(player: Player, rawData: any): Profile
	local self = setmetatable({
		Data = rawData.Data,
		MetaData = rawData.MetaData,
		GlobalUpdates = rawData.GlobalUpdates,
		
		Player = player,
		_is_released = false,
		
		_release_listeners = {},
		_meta_data_listeners = {},
		_hop_ready_listeners = {},
	}, ProfileClass)
	
	return (self :: any) :: Profile
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
	if self._is_released then
		return
	end
	
	self._is_released = true
	
	for _, callback in self._release_listeners do
		task.spawn(callback, self.Data)
	end
	
	table.clear(self._release_listeners)
	table.clear(self._meta_data_listeners)
	table.clear(self._hop_ready_listeners)
end

function ProfileClass:Reconcile(template: any)
	local function reconcileTable(target: any, source: any)
		for key, value in source do
			if target[key] == nil then
				if type(value) == "table" then
					target[key] = table.clone(value)
					reconcileTable(target[key], value)
				else
					target[key] = value
				end
			elseif type(target[key]) == "table" and type(value) == "table" then
				reconcileTable(target[key], value)
			end
		end
	end
	
	reconcileTable(self.Data, template)
end

function ProfileClass:ClearMetaDataListeners()
	table.clear(self._meta_data_listeners)
end

return ProfileClass
