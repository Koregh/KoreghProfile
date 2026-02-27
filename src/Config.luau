--!strict

local RunService = game:GetService("RunService")

local Config = {
	DATA_KEY = "PRODUCTION_V1",

	MOCK_MODE = RunService:IsStudio(),
	DEBUG_MODE = RunService:IsStudio(), -- debug visualization only in Studio

	TEMPLATE = {
		Stats = {
			Wallet = 0,
			Experience = 0,
			Gold = 0,
			Gems = 0,
			Prestige = 0,
		},
		Inventory = {
			Items = {},
			Skins = {},
		},
		Settings = {
			MusicVolume = 0.5,
			SfxVolume = 0.8,
			ShowDamageTags = true,
		},
		Quests = {
			Active = {},
			Completed = {},
			DailyResetTime = 0,
		},
	},
}

local function validateTypes(target: any, template: any, path: string): (boolean, string?)
	for key, expectedValue in pairs(template) do
		local fullPath = path .. "." .. tostring(key)
		local actualValue = target[key]

		if actualValue == nil then
			continue
		end

		local expectedType = type(expectedValue)
		local actualType = type(actualValue)

		if actualType ~= expectedType then
			return false, `{fullPath} deveria ser {expectedType}, mas é {actualType}`
		end

		if expectedType == "table" then
			local ok, err = validateTypes(actualValue, expectedValue, fullPath)
			if not ok then
				return false, err
			end
		end
	end

	return true, nil
end

function Config.Validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "data deve ser uma tabela"
	end

	if type(data.Data) ~= "table" then
		return false, "data.Data deve ser uma tabela"
	end

	if type(data.MetaData) ~= "table" then
		return false, "data.MetaData deve ser uma tabela"
	end

	local ok, err = validateTypes(data.Data, Config.TEMPLATE, "data.Data")
	if not ok then
		return false, err
	end

	return true, nil
end

return Config
