--!strict
local DataProxy = {}
DataProxy.__index = DataProxy

type Operation = "Add" | "Sub" | "Set"

function DataProxy.new(player: Player, path: string, system: any)
	return setmetatable({
		_player = player,
		_path = path,
		_system = system,
	}, DataProxy)
end

function DataProxy:Change(value: number, op: Operation)
	return self._system:Mutate(self._player, self._path, function(old)
		old = old or 0
		if op == "Add" then return old + value end
		if op == "Sub" then return old - value end
		return value
	end)
end

function DataProxy:Insert(item: any)
	return self._system:Mutate(self._player, self._path, function(tbl)
		tbl = tbl or {}
		table.insert(tbl, item)
		return tbl
	end)
end

function DataProxy:Find(key: string, value: any)
	local tbl = self._system:Get(self._player, self._path)
	if type(tbl) ~= "table" then return nil end
	for _, v in ipairs(tbl) do
		if v[key] == value then return v end
	end
	return nil
end

function DataProxy:Patch(idKey: string, idValue: any, changes: {[any]: any})
	return self._system:Mutate(self._player, self._path, function(tbl)
		if type(tbl) ~= "table" then return tbl end
		
		for _, item in ipairs(tbl) do
			if item[idKey] == idValue then
				local function merge(target, source)
					for k, v in pairs(source) do
						if type(v) == "table" and type(target[k]) == "table" then
							merge(target[k], v)
						else
							target[k] = v
						end
					end
				end
				merge(item, changes)
				break
			end
		end
		return tbl
	end)
end

return DataProxy
