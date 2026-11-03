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
            { coords = vector4(23.24, -1105.29, 29.80, 159.43), label = 'Ammu-Nation records clerk' },
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
        -- The range counter.  The target prompt is a small sphere here so it does
        -- not also appear on the Ammu-Nation vending machine inside the building.
        -- Set to nil to fall back to targeting the whole zone polygon above.
        interactionPoint = vector3(22.5, -1104.5, 29.8),
        interactionRadius = 1.5,
        interactionDistance = 2.0,
        shots = 10,
        trainingTimeout = 120000,
        qualification = {
            enabled = false,            -- true = after the last round, pass this minigame to get the licence
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
        reportOptionsLimit = 200,       -- newest reports offered in the case "link report" picker (1-5000)
        warrantDefaultDays = 7,
        warrantMaxDays = 30,
        boloDefaultDays = 7,
        boloMaxDays = 30,
    },
    dateFormat = 'YYYY-MM-DD HH:mm', -- tokens: YYYY MM DD HH mm ss; used for every date/time shown in the MDT
    reports = {
        requireSubject = false,         -- legacy alias of requiredFields.report.subject (either one being true makes it required)
        requireCharge = false,          -- legacy alias of requiredFields.report.charge
        resolveSubjectByName = true,    -- true = a subject that is not a citizen ID is matched to a citizen by exact full name (a unique match is linked)
        allowUnknownSubject = true,     -- true = a subject that matches no citizen is stored as unlinked free text; false = reject with "Subject must be a citizen ID"
        allowCustomCharges = true,      -- true = a charge that is not in the charge list is stored as free text; false = reject it
    },
    -- Which optional form fields must be filled in before a record is saved. The server enforces
    -- this and names the missing field in its error; the terminal marks the field with an asterisk.
    -- Fields not listed here (titles, citizen IDs / plates, the criminal-record charge) are always required.
    requiredFields = {
        report = { subject = false, charge = false, narrative = true },
        case = { summary = true },
        warrant = { reason = true },
        bolo = { description = true },
        criminal = { notes = false },
        medical = { notes = true },
    },
    bolo = {
        resolvePersonByName = true,       -- true = a Person subject that is not a citizen ID is matched to a citizen by exact full name (a unique match is stored as that citizen ID)
        allowUnknownPersonSubject = true, -- true = a Person subject that matches no citizen is stored as free text (name/description); false = reject it with an error
        showLinkedCitizen = true,         -- true = a Person BOLO linked to a citizen shows a separate "Linked citizen ID" row in its details; the Subject is always the text as typed
    },
    charges = {
        { code = 'SPD-01', label = 'Speeding', fine = 250 },
        { code = 'WPN-01', label = 'Unlawful discharge of a firearm', fine = 1500 },
        { code = 'WPN-02', label = 'Possession of an unlicensed firearm', fine = 2500 },
        { code = 'VEH-01', label = 'Reckless driving', fine = 750 },
    },
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if QB and QB.config and QB.config.adopt then
    Config.mdt.roles.policeJobs = QB.config.map(Config.mdt.roles.policeJobs, QB.config.boolean(false), {
        label = 'Police jobs',
        description = 'Lists the job names that receive police access to the MDT. Use the job name as the key and true as the value; removing a row revokes that job’s police role after the resource restarts.',
    })
    Config.mdt.roles.medicalJobs = QB.config.map(Config.mdt.roles.medicalJobs, QB.config.boolean(false), {
        label = 'Medical jobs',
        description = 'Lists the job names that receive medical access to the MDT. Use the job name as the key and true as the value; removing a row revokes that job’s medical role after the resource restarts.',
    })
    Config.mdt.roles.judgeJobs = QB.config.map(Config.mdt.roles.judgeJobs, QB.config.boolean(false), {
        label = 'Judge jobs',
        description = 'Lists the job names that receive judicial access to the MDT. Use the job name as the key and true as the value; removing a row revokes that job’s judge role after the resource restarts.',
    })
    Config.mdt.firearms.lookupMode = QB.config.enum(Config.mdt.firearms.lookupMode, {
        label = 'Firearm lookup mode',
        description = 'Chooses where firearm sale records can be searched. NPC requires players to use a configured records clerk in person, while MDT exposes the lookup from the terminal.',
        options = {
            { value = 'npc', label = 'Records clerk (NPC)' },
            { value = 'mdt', label = 'MDT terminal' },
        },
    })
    Config.mdt.weaponLicence.interactionPoint = QB.config.vector3(Config.mdt.weaponLicence.interactionPoint, {
        label = 'Weapon licence counter',
        description = 'Sets the world position of the weapon-licence range counter where players start the test. The target prompt only appears around this point, so it does not show on other targets in the same building such as the vending machine.',
    })
    Config.mdt.weaponLicence.interactionRadius = QB.config.number(Config.mdt.weaponLicence.interactionRadius, {
        label = 'Weapon licence counter radius',
        description = 'Sets the radius, in game units, of the target sphere around the weapon-licence counter point. Keep it small so neighbouring targets are not included.',
        min = 0.5,
    })

    Config = QB.config.adopt(Config, { descriptions = {
        ['mdt.command'] = 'Sets the client command players run to open the MDT. Enter the command name without a slash; role and on-duty checks still run on the server before the terminal opens.',
        ['mdt.roles.requireOnDuty'] = 'Controls whether authorised police, medical, and judge jobs must also be marked on duty before they can open or use the MDT. Disable it only if this server intentionally grants off-duty access.',
        ['mdt.firearms.shopId'] = 'Identifies the inventory shop whose weapon purchases require a weapon licence and are written to the firearm registry. The value must exactly match the shop ID emitted by qbinventory.',
        ['mdt.firearms.shopRecords'] = 'Defines the in-world firearm records clerks used in NPC lookup mode. Each numbered row needs a coords vector4 and a label; the server only releases a sale record when the player is close to one of these coordinates.',
        ['mdt.weaponLicence.weapon'] = 'Sets the temporary weapon issued for the live-fire licence test. Use the exact inventory weapon name because the server verifies every recorded training shot against this value.',
        ['mdt.weaponLicence.targetModel'] = 'Sets the prop model spawned for each temporary firing-range target. The model must exist and be loadable by the client or the licence session is cancelled when no targets can be created.',
        ['mdt.weaponLicence.targetHeading'] = 'Sets the heading, in degrees, applied to every spawned firing-range target. Change this when the target props face away from the shooting lanes.',
        ['mdt.weaponLicence.range'] = 'Defines the world-space origin for the weapon-licence firing range. Every target offset is added to this vector3 before its target prop is spawned.',
        ['mdt.weaponLicence.zone.points'] = 'Defines the ordered polygon surrounding the entire weapon-licence range. Keep the vector3 points around the mapped interior boundary; clients and the server both use this polygon to cancel sessions when a player leaves.',
        ['mdt.weaponLicence.zone.thickness'] = 'Sets the vertical height, in game units, of the weapon-licence polygon above its lowest configured point. It must cover the usable interior without extending into unrelated floors.',
        ['mdt.weaponLicence.interactionDistance'] = 'Sets how close a player must be to the range interaction zone to begin a weapon-licence session. The same distance is used by both the target prompt and the server-side proximity check.',
        ['mdt.weaponLicence.shots'] = 'Sets the number of temporary training rounds issued and the number of sequential shots required to complete the live-fire portion of a weapon-licence session.',
        ['mdt.weaponLicence.trainingTimeout'] = 'Sets the maximum duration of a weapon-licence range session in milliseconds. When this timer expires, the server ends the session and removes the temporary training weapon.',
        ['mdt.weaponLicence.qualification.enabled'] = 'When enabled, firing every training round is followed by the qualification minigame below, and the licence is only issued if it is passed. When disabled the live-fire test alone issues the licence.',
        ['mdt.weaponLicence.qualification.game'] = 'Selects the kora_lib minigame used for the weapon-licence qualification step. The name must match a registered kora_lib minigame accepted by both proof authorisation and the client player.',
        ['mdt.weaponLicence.qualification.opts.attempts'] = 'Sets how many attempts the configured weapon-licence qualification minigame permits before it returns a failed result.',
        ['mdt.weaponLicence.qualification.opts.zoneSize'] = 'Sets the success-zone size passed to the weapon-licence skillbar minigame. Smaller values make the qualification timing window more difficult.',
        ['mdt.weaponLicence.qualification.opts.timeLimit'] = 'Sets the weapon-licence qualification minigame time limit in milliseconds. A player who does not complete the challenge before this limit fails the session.',
        ['mdt.weaponLicence.targetOffsets'] = 'Defines the ordered vector3 offsets for temporary range targets relative to the configured range origin. Add or remove rows to change how many target props spawn and where each one appears.',
        ['mdt.analysis.ttl'] = 'Sets the total time, in milliseconds, allowed to complete every configured evidence-analysis stage. The server invalidates the active analysis and its one-use proofs when this deadline expires.',
        ['mdt.analysis.stages'] = 'Defines the ordered kora_lib minigames required to analyse ballistic evidence. Each row needs a game name and an opts object; stages run in row order and every successful stage consumes a server-issued one-use proof.',
        ['mdt.operations.searchLimit'] = 'Sets the maximum number of people or vehicle records returned by one MDT search query. Keep this bounded to prevent broad searches from producing oversized database results and UI payloads.',
        ['mdt.operations.recentLimit'] = 'Sets the maximum number of recent cases, warrants, or BOLO records loaded into their MDT lists. This value is inserted into bounded server-owned SQL queries.',
        ['mdt.operations.reportOptionsLimit'] = 'Sets how many of the newest reports are offered in the case link-report picker, which loads every time police or judges open the MDT. Older reports stay linkable by ID. Clamped to 1-5000.',
        ['mdt.operations.warrantDefaultDays'] = 'Sets the default number of days prefilled when a judge creates a warrant. The submitted duration is clamped between one day and the configured warrant maximum.',
        ['mdt.operations.warrantMaxDays'] = 'Sets the longest warrant duration, in days, that the server will accept. Longer submitted values are reduced to this limit before the warrant is stored.',
        ['mdt.operations.boloDefaultDays'] = 'Sets the default number of days prefilled when an authorised user creates a BOLO. The submitted duration is clamped between one day and the configured BOLO maximum.',
        ['mdt.operations.boloMaxDays'] = 'Sets the longest BOLO duration, in days, that the server will accept. Longer submitted values are reduced to this limit before the BOLO is stored.',
        ['mdt.dateFormat'] = 'Sets how every MDT date and time is displayed. Use the tokens YYYY, MM, DD, HH, mm and ss, for example DD/MM/YYYY HH:mm. Times are shown in the database server time zone.',
        ['mdt.reports.requireSubject'] = 'When enabled the server rejects incident reports that have no subject. Leave it off to allow reports with no suspect.',
        ['mdt.reports.resolveSubjectByName'] = 'When enabled, a report subject that is not a citizen ID is looked up by exact, case-insensitive full name and linked when exactly one citizen matches. Several matches are rejected so the officer can use the citizen ID.',
        ['mdt.reports.allowUnknownSubject'] = 'When enabled, a report subject that matches no citizen is saved as unlinked free text. When disabled the report is rejected with the message "Subject must be a citizen ID".',
        ['mdt.reports.allowCustomCharges'] = 'When enabled, a report charge that is not in the charge catalogue is saved as free text on the report (no criminal record entry is created). When disabled it is rejected and the officer must pick a catalogue charge.',
        ['mdt.reports.requireCharge'] = 'When enabled the server rejects incident reports without a charge. Whether a charge outside the catalogue is accepted is controlled by mdt.reports.allowCustomCharges.',
        ['mdt.bolo.resolvePersonByName'] = 'When enabled, a Person BOLO subject that is not a known citizen ID is looked up by exact, case-insensitive full name. A single match links the BOLO to the profile of that citizen; the BOLO still shows the subject exactly as typed. Several matches are rejected so the officer can use the citizen ID.',
        ['mdt.bolo.showLinkedCitizen'] = 'When enabled, the details of a Person BOLO that is linked to a citizen (exact citizen ID or exact unique full name) show a separate Linked citizen ID row. The Subject column and field always show exactly what the officer typed.',
        ['mdt.bolo.allowUnknownPersonSubject'] = 'When enabled, a Person BOLO subject that matches no citizen ID or name is stored as free text (for example a name or description). When disabled the BOLO is rejected with a clear message.',
        ['mdt.requiredFields.report.subject'] = 'When enabled, incident reports must name an existing subject citizen ID. Same as the older mdt.reports.requireSubject option, which still works.',
        ['mdt.requiredFields.report.charge'] = 'When enabled, incident reports must carry a charge from the charge catalogue. Same as the older mdt.reports.requireCharge option, which still works.',
        ['mdt.requiredFields.report.narrative'] = 'When enabled, incident reports must include an incident narrative. Disable it to allow reports with only a title.',
        ['mdt.requiredFields.case.summary'] = 'When enabled, a new case must include an investigation summary.',
        ['mdt.requiredFields.warrant.reason'] = 'When enabled, a warrant must include a probable cause / reason.',
        ['mdt.requiredFields.bolo.description'] = 'When enabled, a BOLO must include a description and instructions.',
        ['mdt.requiredFields.criminal.notes'] = 'When enabled, a criminal record entry must include notes.',
        ['mdt.requiredFields.medical.notes'] = 'When enabled, a medical record must include treatment notes.',
        ['mdt.charges'] = 'Defines the charge catalogue seeded into the MDT database when it becomes ready. Each numbered row needs a unique code, display label, and non-negative fine; existing database rows with the same code are left intact.',
    } })
end
