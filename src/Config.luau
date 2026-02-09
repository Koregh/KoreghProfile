--!strict

local RunService = game:GetService("RunService")

local Config = {
	DATA_KEY = "PRODUCTION_V1",
	
	SESSION_LOCK_TIMEOUT = 1200, -- 20 minutes
	LOAD_MAX_RETRIES = 8,
	AUTO_SAVE_INTERVAL = 30, -- seconds
	
	MOCK_MODE = RunService:IsStudio(),
	DEBUG_MODE = true,
	
	-- Default Data Template
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
	
	if type(data.Stats) ~= "table" then
		return false, "Stats must be a table"
	end
	
	return true, nil
end

return Config
