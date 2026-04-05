--!strict
local GlobalUpdates = require(script.Parent.GlobalUpdates)

export type Callback = (data: any) -> ()

export type Profile = {
	Data          : { [string]: any },
	MetaData      : {
		ProfileCreateTime : number,
		SessionLoadCount  : number,
		ActiveSession     : string?,
		ForceLoadSteps    : number,
		UserIds           : { number },
		_last_ping        : number,
	},
	GlobalUpdates : typeof(GlobalUpdates.new()),
	Player        : Player,

	_is_released         : boolean,
	_release_listeners   : { Callback },
	_hop_ready_listeners : { Callback },

	AddUserId       : (self: Profile, userId: number) -> (),
	GetGlobalUpdates: (self: Profile) -> typeof(GlobalUpdates.new()),
	IsActive        : (self: Profile) -> boolean,
	ListenToRelease : (self: Profile, callback: Callback) -> (),
	ListenToHopReady: (self: Profile, callback: Callback) -> (),
	Release         : (self: Profile) -> (),
	Reconcile       : (self: Profile, template: any) -> (),
}

local ProfileClass = {}
ProfileClass.__index = ProfileClass

local function deepClone(t: any): any
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepClone(v)
	end
	return copy
end

function ProfileClass.new(player: Player, rawData: any): Profile
	return (setmetatable({
		Data          = rawData.Data,
		MetaData      = rawData.MetaData,
		GlobalUpdates = GlobalUpdates.new(rawData.GlobalUpdates),

		Player       = player,
		_is_released = false,

		_release_listeners   = {} :: { Callback },
		_hop_ready_listeners = {} :: { Callback },
	}, ProfileClass) :: any) :: Profile
end

function ProfileClass:AddUserId(userId: number)
	if not self.MetaData.UserIds then
		self.MetaData.UserIds = {}
	end
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

	self._release_listeners   = {}
	self._hop_ready_listeners = {}
end


function ProfileClass:Reconcile(template: any)
	local function reconcileTable(target: any, source: any)
		for key, value in pairs(source) do
			if target[key] == nil then
				target[key] = deepClone(value) 
			elseif type(target[key]) == "table" and type(value) == "table" then
				reconcileTable(target[key], value)
			end
		end
	end
	reconcileTable(self.Data, template)
end

return ProfileClass
