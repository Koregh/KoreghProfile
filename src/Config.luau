--!strict

local Config = {
	
	DATA_KEY = "PRODUCTION_V1",
	
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
	SESSION_LOCK_TIMEOUT = 1200,
	
	AUTO_SAVE_INTERVAL = 30,
	
	LOAD_MAX_RETRIES = 8,
	
	MOCK_MODE = game:GetService("RunService"):IsStudio(),


	DEBUG_MODE = true, 
}

function Config.Validate(data: any): (boolean, string?)
	return true
end

return Config
