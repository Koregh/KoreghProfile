--!strict
return {
    VERSION = "1.0.0",
    SETTING = {
        AutoSaveInterval = 30,
        LoadMaxRetries = 8,
        SessionLockTimeout = 1200, 
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
        },
        GlobalUpdates = {0, {}} 
    }
}
