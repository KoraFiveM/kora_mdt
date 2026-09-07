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
        -- The Ammu-Nation-with-range interior.  Keep this footprint in sync
        -- with the mapped building, rather than limiting the test to a small
        -- circle by the counter: the firing lanes and their targets are at
        -- the north end of the same building.
        zone = {
            points = {
                vector3(20.61, -1116.66, 28.99),
                vector3(25.83, -1105.59, 31.73),
                vector3(18.55, -1102.30, 30.45),
                vector3(29.50, -1071.96, 29.84),
                vector3(18.90, -1068.10, 29.94),
                vector3(16.88, -1069.09, 29.53),
                vector3(2.52, -1108.76, 30.46),
                vector3(13.96, -1113.49, 31.19),
                vector3(14.04, -1114.59, 29.30),
            },
            thickness = 4.0,
        },
        interactionDistance = 2.0,
        shots = 10,
        trainingTimeout = 120000,
        qualification = {
            game = 'skillbar',
            opts = { attempts = 1, zoneSize = 0.14, timeLimit = 8000 },
        },
        targetOffsets = {
            -- The range runs diagonally through the configured building poly.
            vector3(-4.0, 12.0, 0.0), vector3(-3.0, 14.0, 0.4), vector3(-2.0, 16.0, -0.2),
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
    operations = {
        searchLimit = 25,
        recentLimit = 50,
        warrantDefaultDays = 7,
        warrantMaxDays = 30,
        boloDefaultDays = 7,
        boloMaxDays = 30,
    },
    charges = {
        { code = 'SPD-01', label = 'Speeding', fine = 250 },
        { code = 'WPN-01', label = 'Unlawful discharge of a firearm', fine = 1500 },
        { code = 'WPN-02', label = 'Possession of an unlicensed firearm', fine = 2500 },
        { code = 'VEH-01', label = 'Reckless driving', fine = 750 },
    },
}

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
