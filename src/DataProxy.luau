--!strict

local DataProxy = {}
DataProxy.__index = DataProxy

type Operation = "Add" | "Sub" | "Set"

function DataProxy.new(player: Player, path: string, system: any)
	return setmetatable({
		_player = player,
		_path   = path,
		_system = system,
	}, DataProxy)
end

--[[
	To change
	Apply a numeric operation without path value.
	"Add" adds, "Sub" subtracts, "Set" replaces.
]]
function DataProxy:Change(value: number, op: Operation): boolean
	local current = self._system:Get(self._player, self._path)
	if current == nil then
		warn(`[DataProxy] Path '{self._path}' not found for {self._player.Name}`)
		return false
	end
	if type(current) ~= "number" then
		warn(`[DataProxy] Path '{self._path}' is not number (it is {typeof(current)})`)
		return false
	end

	return self._system:Mutate(self._player, self._path, function(old: number)
		old = old or 0
		if op == "Add" then return old + value end
		if op == "Sub" then return old - value end
		return value -- "Set"
	end)
end

--[[
	Insert
	Inserts an item into the path list.
]]
function DataProxy:Insert(item: any): boolean
	return self._system:Mutate(self._player, self._path, function(tbl: any)
		if type(tbl) ~= "table" then
			warn(`[DataProxy] Caminho '{self._path}' não é uma tabela`)
			return tbl
		end
		table.insert(tbl, item)
		return tbl
	end)
end

--[[
Find
	Returns the first item in the list where item[key] == value.
]]
function DataProxy:Find(key: string, value: any): any?
	local tbl = self._system:Get(self._player, self._path)
	if type(tbl) ~= "table" then return nil end

	for _, v in ipairs(tbl) do
		if type(v) == "table" and v[key] == value then
			return v
		end
	end
	return nil
end

--[[
	Patch
	Applies a merge to the fields of a list item identified by idKey == idValue.
	Deep merge: subtables are merged recursively.
	changes is cloned to avoid external mutations.
]]
function DataProxy:Patch(idKey: string, idValue: any, changes: { [any]: any }): boolean
	-- Clona changes para isolar de mutações externas após o call
	local function deepClone(t: any): any
		if type(t) ~= "table" then return t end
		local copy = {}
		for k, v in pairs(t) do copy[k] = deepClone(v) end
		return copy
	end

	local safeChanges = deepClone(changes)

	return self._system:Mutate(self._player, self._path, function(tbl: any)
		if type(tbl) ~= "table" then
			warn(`[DataProxy] Caminho '{self._path}' não é uma tabela`)
			return tbl
		end

		local function merge(target: any, source: any)
			for k, v in pairs(source) do
				if type(v) == "table" and type(target[k]) == "table" then
					merge(target[k], v)
				else
					target[k] = v
				end
			end
		end

		for _, item in ipairs(tbl) do
			if type(item) == "table" and item[idKey] == idValue then
				merge(item, safeChanges)
				break
			end
		end

		return tbl
	end)
end

return DataProxy
