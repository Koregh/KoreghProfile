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

function Config.Validate(data: any): (boolean, string?)
	if type(data) ~= "table" then
		return false, "Data must be a table"
	end

	if type(data.Data) ~= "table" then
		return false, "data.Data must be a table"
	end

	if type(data.MetaData) ~= "table" then
		return false, "data.MetaData must be a table"
	end

	if type(data.Data.Stats) ~= "table" then
		return false, "data.Data.Stats must be a table"
	end

	return true, nil
end

return Config
