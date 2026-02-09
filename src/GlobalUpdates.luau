--!strict
local GlobalUpdates = {}
GlobalUpdates.__index = GlobalUpdates

function GlobalUpdates.new(updatesTable)
	return setmetatable({
		_updates = updatesTable or {0, {}}
	}, GlobalUpdates)
end

function GlobalUpdates:GetActiveUpdates()
	return self._updates[2]
end

function GlobalUpdates:ClearUpdate(updateId: number)
	for i, update in ipairs(self._updates[2]) do
		if update[1] == updateId then
			table.remove(self._updates[2], i)
			break
		end
	end
end

return GlobalUpdates
