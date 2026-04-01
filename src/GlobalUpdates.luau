--!strict

export type Update      = { [any]: any }
export type UpdateEntry = { number, Update }

export type GlobalUpdates = {
	GetActiveUpdates: (self: GlobalUpdates) -> { UpdateEntry },
	AddUpdate       : (self: GlobalUpdates, data: Update) -> (),
	ClearUpdate     : (self: GlobalUpdates, updateId: number) -> (),
	Serialize       : (self: GlobalUpdates) -> { any },
}

local GlobalUpdatesClass = {}
GlobalUpdatesClass.__index = GlobalUpdatesClass

--[[
	GlobalUpdatesClass.new
	raw = { nextId, entries } conforme serializado no DataStore.
	Default: { 0, {} } — nextId começa em 0.
]]
function GlobalUpdatesClass.new(raw: { any }?): GlobalUpdates
	local data = raw or { 0, {} }
	return (setmetatable({
		_nextId  = (data[1] :: number) or 0,
		_entries = (data[2] :: { UpdateEntry }) or {},
	}, GlobalUpdatesClass) :: any) :: GlobalUpdates
end

function GlobalUpdatesClass:GetActiveUpdates(): { UpdateEntry }
	return self._entries
end

function GlobalUpdatesClass:AddUpdate(data: Update)
	local id     = self._nextId
	self._nextId += 1
	table.insert(self._entries, { id, data })
end

function GlobalUpdatesClass:ClearUpdate(updateId: number)
	for i, entry in ipairs(self._entries) do
		if entry[1] == updateId then
			table.remove(self._entries, i)
			return
		end
	end
end

-- Serializa de volta para o formato do DataStore
function GlobalUpdatesClass:Serialize(): { any }
	return { self._nextId, self._entries }
end

return GlobalUpdatesClass
