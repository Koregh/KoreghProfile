--!strict
local ValueMirror = {}

local function GetValueType(value: any): string
	local t = typeof(value)
	if t == "number" then return "NumberValue"
	elseif t == "boolean" then return "BoolValue"
	elseif t == "string" then return "StringValue"
	else return "StringValue" 
	end
end

function ValueMirror.Sync(parent: Instance, data: {[any]: any})
	for key, value in pairs(data) do
		local name = tostring(key)
		
		if typeof(value) == "table" then
			local folder = parent:FindFirstChild(name) or Instance.new("Folder")
			folder.Name = name
			folder.Parent = parent
			ValueMirror.Sync(folder, value)
		else
			local className = GetValueType(value)
			local valueObj = parent:FindFirstChild(name)
			
			if not valueObj or valueObj.ClassName ~= className then
				if valueObj then valueObj:Destroy() end
				valueObj = Instance.new(className)
				valueObj.Name = name
				valueObj.Parent = parent
			end
			(valueObj :: any).Value = value
		end
	end
end

return ValueMirror
