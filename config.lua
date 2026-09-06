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
        weapon = 'weapon_pistol',
        targetModel = 'prop_target_blue_arrow',
        targetHeading = 180.0,
        range = vector3(22.5, -1104.5, 29.8),
        interactionDistance = 2.0,
        shots = 10,
        trainingTimeout = 120000,
        qualification = {
            game = 'skillbar',
            opts = { attempts = 1, zoneSize = 0.14, timeLimit = 8000 },
        },
        targetOffsets = {
            vector3(0.0, 12.0, 0.0), vector3(-2.0, 14.0, 0.4), vector3(2.0, 16.0, -0.2),
        },
    },
    analysis = {
        ttl = 300000,                  -- ms allowed to finish all evidence-analysis stages
        stages = {
            { game = 'skillbar', opts = { attempts = 1 } },                 -- microscopy alignment
            { game = 'circuit', opts = { attempts = 1 } },                  -- ballistic comparison
            { game = 'pinpad', opts = { attempts = 1 } },                   -- registry confirmation; PIN is generated server-side
        },
    },
    charges = {
        { code = 'SPD-01', label = 'Speeding', fine = 250 },
        { code = 'WPN-01', label = 'Unlawful discharge of a firearm', fine = 1500 },
        { code = 'WPN-02', label = 'Possession of an unlicensed firearm', fine = 2500 },
        { code = 'VEH-01', label = 'Reckless driving', fine = 750 },
    },
}
