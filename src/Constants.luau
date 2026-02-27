--!strict
return {
	VERSION = "1.0.0",
	SETTING = {
		AutoSaveInterval = 30,       -- seconds between auto-saves
		LoadMaxRetries = 8,          -- max attempts to load a profile
		LoadRetryDelay = 2,          -- seconds between load retries
		LoadTimeout = 10,            -- seconds to wait for profile in GetProfile
		SessionLockTimeout = 1200,   -- seconds before a stale session lock expires
		AssumeSessionLockForce = false,
	},
	STRUCTURE = {
		Data = {},
		MetaData = {
			ProfileCreateTime = 0,
			SessionLoadCount = 0,
			ActiveSession = nil,
			ForceLoadSteps = 0,
			UserIds = {},
			_last_save = 0,
		},
		GlobalUpdates = { 0, {} },
	},
}
