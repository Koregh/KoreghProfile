--!strict

local ValueMirror = {}

local TYPE_TO_CLASS: { [string]: string } = {
	number = "NumberValue",
	boolean = "BoolValue",
	string = "StringValue",
}

function ValueMirror.Sync(parent: Instance, data: { [any]: any })
	-- Track which keys are present in the new data so we can remove stale children.
	local seen: { [string]: boolean } = {}

	for key, value in pairs(data) do
		local name = tostring(key)
		seen[name] = true

		if type(value) == "table" then
			local folder = parent:FindFirstChild(name)
			if not folder or not folder:IsA("Folder") then
				if folder then
					folder:Destroy()
				end
				folder = Instance.new("Folder")
				folder.Name = name
				folder.Parent = parent
			end
			ValueMirror.Sync(folder :: Instance, value)
		else
			local className = TYPE_TO_CLASS[typeof(value)] or "StringValue"
			local displayValue = if typeof(value) == "string" then value else tostring(value)

			local valueObj = parent:FindFirstChild(name)

			-- Only recreate the object if the class changed (e.g. number -> string).
			if not valueObj or valueObj.ClassName ~= className then
				if valueObj then
					valueObj:Destroy()
				end
				valueObj = Instance.new(className)
				valueObj.Name = name
				valueObj.Parent = parent
			end

			local current = (valueObj :: any).Value
			if className == "StringValue" and typeof(value) ~= "string" then
				if current ~= displayValue then
					(valueObj :: any).Value = displayValue
				end
			else
				if current ~= value then
					(valueObj :: any).Value = value
				end
			end
		end
	end

	for _, child in parent:GetChildren() do
		if not seen[child.Name] then
			child:Destroy()
		end
	end
end

return ValueMirror
