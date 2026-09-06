Config = Config or {}

Config.mdt = {
    command = 'mdt',
    roles = {
        policeJobs = { police = true },
        medicalJobs = { ambulance = true },
        judgeJobs = { judge = true },
        requireOnDuty = true,
    },
    firearms = {
        shopId = 'ammunation',          -- only this civilian shop requires a weapon licence and registers purchases
        lookupMode = 'npc',             -- 'npc' requires the configured counter target; 'mdt' enables the terminal lookup
        shopRecords = {
            { coords = vector4(22.09, -1107.28, 29.80, 160.0), label = 'Ammu-Nation records clerk' },
        },
    },
    weaponLicence = {
        range = vector3(22.5, -1104.5, 29.8),
        interactionDistance = 2.0,
        targetRadius = 0.55,
        requiredScore = 8,
        shots = 10,
        targetOffsets = {
            vector3(0.0, 12.0, 0.0), vector3(-2.0, 14.0, 0.4), vector3(2.0, 16.0, -0.2),
        },
    },
    charges = {
        { code = 'SPD-01', label = 'Speeding', fine = 250 },
        { code = 'WPN-01', label = 'Unlawful discharge of a firearm', fine = 1500 },
        { code = 'WPN-02', label = 'Possession of an unlicensed firearm', fine = 2500 },
        { code = 'VEH-01', label = 'Reckless driving', fine = 750 },
    },
}
