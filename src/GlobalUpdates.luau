--!strict

export type Update = { [any]: any }
export type UpdateEntry = { number, Update }

export type GlobalUpdates = {
	GetActiveUpdates: (self: GlobalUpdates) -> { UpdateEntry },
	AddUpdate: (self: GlobalUpdates, data: Update) -> (),
	ClearUpdate: (self: GlobalUpdates, updateId: number) -> (),
}

local GlobalUpdatesClass = {}
GlobalUpdatesClass.__index = GlobalUpdatesClass

function GlobalUpdatesClass.new(updatesTable: { any }?)
	-- Default to { 1, {} } — nextId starts at 1, entries empty
	local raw = updatesTable or { 1, {} }
	return setmetatable({
		_nextId = raw[1] :: number,
		_entries = raw[2] :: { UpdateEntry },
	}, GlobalUpdatesClass)
end

function GlobalUpdatesClass:GetActiveUpdates(): { UpdateEntry }
	return self._entries
end

function GlobalUpdatesClass:AddUpdate(data: Update)
	local id = self._nextId
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

function GlobalUpdatesClass:Serialize(): { any }
	return { self._nextId, self._entries }
end

return GlobalUpdatesClass
