local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
dofile('shared/required.lua')
dofile('server/main.lua')

local function start(src)
    handle.ensurePlayer(src)
    handle.net('qbmdt:server:startWeaponLicence', src)
end

local function fireRounds(src, from, to, overrides)
    overrides = overrides or {}
    for shot = from, to do
        handle.event('qbinventory:server:trainingRoundFired', src, {
            owner = overrides.owner or 'kora_mdt',
            weapon = overrides.weapon or Config.mdt.weaponLicence.weapon,
            shot = shot,
        })
    end
end

local function latestAuthorization(src)
    for index = #handle.authorizations, 1, -1 do
        if handle.authorizations[index].src == src then return handle.authorizations[index] end
    end
end

local function resetObservations()
    handle.clientEvents = {}
    handle.timeouts = {}
    handle.notifications = {}
    handle.starts = {}
    handle.stops = {}
    handle.authorizations = {}
    handle.consumes = {}
    handle.metadataWrites = {}
    handle.sqlWrites = 0
    handle.sqlInserts = {}
    handle.sqlUpdates = {}
    handle.sqlSingle = nil
    handle.sqlInsertError = nil
    handle.sqlQuery = nil
    handle.startTrainingResult = true
    handle.startTrainingError = nil
    handle.authorizeEnabled = true
    handle.metadataResult = true
    handle.onLicenceWrite = nil
end

h.test('all remote gameplay events use bounded kora_lib ingress', function()
    local expected = {
        ['qbmdt:server:open'] = true,
        ['qbmdt:server:beginAnalysis'] = true,
        ['qbmdt:server:cancelAnalysis'] = true,
        ['qbmdt:server:analysisStage'] = true,
        ['qbmdt:server:startWeaponLicence'] = true,
        ['qbmdt:server:completeWeaponLicence'] = true,
        ['qbmdt:server:cancelWeaponLicence'] = true,
    }
    for name in pairs(expected) do
        local registered = QB.events.registry[name]
        h.assertTrue(registered ~= nil, name .. ' must use QB.events.register')
        local limit = registered.options and registered.options.rateLimit
        h.assertTrue(limit ~= nil and limit.max > 0 and limit.window > 0, name .. ' must be rate limited')
    end
    local startLimit = QB.events.registry['qbmdt:server:startWeaponLicence'].options.rateLimit
    h.assertEqual(startLimit.max, 1)
    h.assertEqual(startLimit.window, 2000)
    h.assertTrue(next(handle.netHandlers) == nil, 'gameplay ingress must not bypass kora_lib registration')
end)

h.test('MDT open returns the authorised role and explains access denial', function()
    resetObservations()
    handle.ensurePlayer(90, { job = { name = 'ambulance', onduty = true } })
    handle.net('qbmdt:server:open', 90)
    local opened = handle.eventsNamed('qbmdt:client:open', 90)
    h.assertEqual(#opened, 1)
    h.assertEqual(opened[1].args[1], 'medical')

    handle.ensurePlayer(91, { job = { name = 'police', onduty = false } })
    handle.net('qbmdt:server:open', 91)
    h.assertEqual(#handle.eventsNamed('qbmdt:client:open', 91), 0)
    h.assertEqual(#handle.notifications, 1)
    h.assertEqual(handle.notifications[1].src, 91)
    h.assertEqual(handle.notifications[1].payload.type, 'error')
end)

h.test('operational callbacks are role-gated and citizen searches are bounded', function()
    resetObservations()
    handle.ensurePlayer(92, { job = { name = 'ambulance', onduty = true } })
    local search = QB.callback.registry['qbmdt:server:searchVehicles']
    local rows, err = search(92, 'ABC')
    h.assertEqual(rows, nil)
    h.assertEqual(err, 'not authorised')

    handle.ensurePlayer(93)
    rows, err = QB.callback.registry['qbmdt:server:searchPeople'](93, 'x')
    h.assertEqual(rows, nil)
    h.assertEqual(err, 'enter at least two characters')
    local captured
    handle.sqlQuery = function(query, params) captured = { query = query, params = params }; return {} end
    rows = QB.callback.registry['qbmdt:server:searchPeople'](93, 'Jane_20%')
    h.assertEqual(#rows, 0)
    h.assertTrue(captured.query:find('LIMIT 25', 1, true) ~= nil, 'search limit must be server-owned')
    h.assertEqual(captured.params[1], 'Jane_20%', 'search input must stay a bound parameter rather than SQL syntax')
end)

local function readyMdt()
    handle.sqlQuery = function() return { { code = 'SPD-01', label = 'Speeding', fine = 250 } } end
    handle.event('qbmdt:server:databaseReady')
end

h.test('incident reports validate server records, create charge history, and audit', function()
    resetObservations()
    handle.ensurePlayer(94)
    readyMdt()
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) then return { citizenid = params[1] } end
    end
    local create = QB.callback.registry['qbmdt:server:createReport']
    Config.mdt.reports.allowCustomCharges = false
    local id, err = create(94, { title = 'Traffic stop', narrative = 'Vehicle failed to stop.', citizenid = 'CID000777', charge = 'bad' })
    Config.mdt.reports.allowCustomCharges = true
    h.assertEqual(id, nil)
    h.assertTrue(err:find('is not in the charge list', 1, true) ~= nil)

    id, err = create(94, { title = 'Traffic stop', narrative = 'Vehicle failed to stop.', citizenid = 'CID000777', charge = 'spd-01' })
    h.assertEqual(id, 1)
    h.assertEqual(handle.sqlInserts[1].params[5], 'SPD-01')
    h.assertTrue(handle.sqlInserts[2].query:find('qbmdt_criminal_records', 1, true) ~= nil,
        'charged report must be reflected in criminal history')
    h.assertTrue(handle.sqlInserts[3].query:find('qbmdt_audit_log', 1, true) ~= nil,
        'report creation must be audited')
end)

h.test('report subject and charge are optional by default and enforced by config', function()
    resetObservations()
    handle.ensurePlayer(94)
    readyMdt()
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) and params[1] == 'CID000777' then return { citizenid = params[1] } end
    end
    local create = QB.callback.registry['qbmdt:server:createReport']
    local base = { title = 'Noise complaint', narrative = 'Loud party.' }
    h.assertEqual(create(94, base), 1)
    h.assertEqual(#handle.sqlInserts >= 1 and handle.sqlInserts[1].query:find('criminal', 1, true), nil)

    local _, err = create(94, { title = 'x', narrative = 'y', citizenid = 'CID999999' })
    h.assertTrue(err:find('not found', 1, true) ~= nil, 'unknown subject must be rejected')

    Config.mdt.reports.requireSubject = true
    _, err = create(94, base)
    h.assertEqual(err, 'Subject citizen ID is required.')
    Config.mdt.reports.requireSubject = false
    Config.mdt.reports.requireCharge = true
    _, err = create(94, { title = 'x', narrative = 'y', citizenid = 'CID000777' })
    h.assertEqual(err, 'A charge is required.')
    Config.mdt.reports.requireCharge = false
end)

h.test('requiredFields config drives every create form with specific errors', function()
    resetObservations()
    handle.ensurePlayer(94)
    readyMdt()
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) then return { citizenid = params[1] } end
        if query:find('qbmdt_charges', 1, true) then return { code = 'SPD-01' } end
    end
    local reg = QB.callback.registry
    local fields = Config.mdt.requiredFields

    local _, err = reg['qbmdt:server:createReport'](94, { title = 'T' })
    h.assertEqual(err, 'Incident narrative is required.')
    fields.report.narrative = false
    h.assertEqual(reg['qbmdt:server:createReport'](94, { title = 'T' }), 1)
    fields.report.narrative = true
    _, err = reg['qbmdt:server:createReport'](94, { narrative = 'n' })
    h.assertEqual(err, 'Title is required.')
    fields.report.subject = true
    _, err = reg['qbmdt:server:createReport'](94, { title = 'T', narrative = 'n' })
    h.assertEqual(err, 'Subject citizen ID is required.')
    fields.report.subject = false

    _, err = reg['qbmdt:server:createCase'](94, { title = 'C' })
    h.assertEqual(err, 'Investigation summary is required.')
    _, err = reg['qbmdt:server:createWarrant'](94, { citizenid = 'CID000777' })
    h.assertEqual(err, 'Probable cause / reason is required.')
    fields.warrant.reason = false
    h.assertTrue(reg['qbmdt:server:createWarrant'](94, { citizenid = 'CID000777' }) ~= nil)
    fields.warrant.reason = true
    _, err = reg['qbmdt:server:createWarrant'](94, { reason = 'r' })
    h.assertEqual(err, 'Citizen ID is required.')
    _, err = reg['qbmdt:server:createBolo'](94, { subject_type = 'person', identifier = 'CID000777', title = 'T' })
    h.assertEqual(err, 'Description and instructions is required.')
    local ok
    ok, err = reg['qbmdt:server:addCriminal'](94, 'CID000777', '', '')
    h.assertEqual(err, 'Charge is required.')
    fields.criminal.notes = true
    ok, err = reg['qbmdt:server:addCriminal'](94, 'CID000777', 'SPD-01', '')
    h.assertEqual(err, 'Notes is required.')
    fields.criminal.notes = false
end)

h.test('every list returns readable time strings, never tables', function()
    resetObservations()
    handle.ensurePlayer(94)
    handle.sqlQuery = function() return { { id = 1, updated_at = { year = 2026, month = 10, day = 31, hour = 22, min = 5 } },
        { id = 2, updated_at = '2026-10-31 22:16:09' }, { id = 3, updated_at = 1793484969000 } } end
    local rows = QB.callback.registry['qbmdt:server:reports'](94)
    h.assertEqual(rows[1].updated_at, '2026-10-31 22:05')
    h.assertEqual(rows[2].updated_at, '2026-10-31 22:16')
    h.assertEqual(type(rows[3].updated_at), 'string')
end)

h.test('person BOLOs accept citizen ID, unique name, or free text and report clear errors', function()
    resetObservations()
    handle.ensurePlayer(96)
    readyMdt()
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) and params[1] == 'ABC12345' then return { citizenid = 'ABC12345' } end
    end
    local names = { ['jane doe'] = { { citizenid = 'ABC12345' } }, twin = { { citizenid = 'A' }, { citizenid = 'B' } } }
    handle.sqlQuery = function(query, params)
        if query:find('LOWER(TRIM(`name`))', 1, true) then return names[params[1]:lower()] or {} end
        return {}
    end
    local create = QB.callback.registry['qbmdt:server:createBolo']
    local function make(identifier)
        return create(96, { subject_type = 'person', identifier = identifier, title = 'Wanted', description = 'Detain.', days = 1 })
    end
    local function subject() return handle.sqlInserts[#handle.sqlInserts - 1].params[2] end
    h.assertTrue(make('ABC12345') ~= nil)
    h.assertEqual(subject(), 'ABC12345')
    h.assertTrue(make('Jane Doe') ~= nil)
    h.assertEqual(subject(), 'ABC12345')
    h.assertTrue(make('RaVn') ~= nil)
    h.assertEqual(subject(), 'RaVn')
    local id, err = make('twin')
    h.assertEqual(id, nil)
    h.assertTrue(err:find('citizen ID', 1, true) ~= nil)
    Config.mdt.bolo.allowUnknownPersonSubject = false
    id, err = make('Nobody Here')
    Config.mdt.bolo.allowUnknownPersonSubject = true
    h.assertEqual(id, nil)
    h.assertTrue(err:find('No citizen matches', 1, true) ~= nil)
    id, err = create(96, { subject_type = 'person', identifier = '', title = 'x', description = 'y' })
    h.assertEqual(err, 'Enter a citizen ID or name for the subject.')
end)

h.test('report creation succeeds for empty, citizen ID, name and free-text subjects and charges', function()
    resetObservations()
    local author = handle.ensurePlayer(97)
    readyMdt()
    local NULL = QB.sql.NULL
    local people = { CID000777 = true }
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) and people[params[1]] then return { citizenid = params[1] } end
    end
    handle.sqlQuery = function(query, params)
        if query:find('LOWER(TRIM(`name`))', 1, true) then
            if params[1]:lower() == 'known person' then return { { citizenid = 'CID000777' } } end
            if params[1]:lower() == 'twin' then return { { citizenid = 'A' }, { citizenid = 'B' } } end
        end
        return {}
    end
    local create = QB.callback.registry['qbmdt:server:createReport']
    local function report(extra)
        local input = { title = 'Incident', narrative = 'Something happened.' }
        for k, v in pairs(extra or {}) do input[k] = v end
        local before = #handle.sqlInserts
        local id, err = create(97, input)
        return id, err, handle.sqlInserts[before + 1]
    end
    -- params: title, narrative, subject_citizenid, subject_text, charge_code, charge_text, author
    local id, err, insert = report({ citizenid = '', charge = 'Speeding' })
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(#insert.params, 7, 'no nil holes in the bind list')
    h.assertEqual(insert.params[3], NULL)
    h.assertEqual(insert.params[4], NULL)
    h.assertEqual(insert.params[5], 'SPD-01')
    h.assertEqual(insert.params[6], NULL)
    h.assertEqual(insert.params[7], author.citizenid)

    id, err, insert = report({ charge = 'Trespassing' })
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(#insert.params, 7)
    h.assertEqual(insert.params[5], NULL)
    h.assertEqual(insert.params[6], 'Trespassing')

    id, err, insert = report({ citizenid = 'CID000777', charge = 'Speeding' })
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], 'CID000777')

    id, err, insert = report({ citizenid = 'Joe Jones', charge = 'Possession of an unlicensed firearm' })
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], NULL)
    h.assertEqual(insert.params[4], 'Joe Jones')
    h.assertEqual(insert.params[6], 'Possession of an unlicensed firearm', 'a charge outside the catalogue is kept as text')

    id, err, insert = report({ citizenid = 'known person' })
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], 'CID000777', 'an exact unique name links the citizen')

    id, err = report({ citizenid = 'twin' })
    h.assertEqual(id, nil)
    h.assertTrue(err:find('More than one citizen', 1, true) ~= nil)

    Config.mdt.reports.allowUnknownSubject = false
    id, err = report({ citizenid = 'Joe Jones' })
    Config.mdt.reports.allowUnknownSubject = true
    h.assertEqual(id, nil)
    h.assertTrue(err:find('Subject must be a citizen ID', 1, true) ~= nil)

    Config.mdt.reports.allowCustomCharges = false
    id, err = report({ charge = 'Trespassing' })
    Config.mdt.reports.allowCustomCharges = true
    h.assertEqual(id, nil)
    h.assertTrue(err:find('"Trespassing" is not in the charge list', 1, true) ~= nil)

    handle.sqlInsertError = { match = 'qbmdt_reports', message = 'boom' }
    id, err = report({})
    h.assertEqual(id, nil)
    h.assertTrue(err:find('database error', 1, true) ~= nil, 'a failed insert returns a specific message')
    handle.sqlInsertError = nil
end)

h.test('BOLO subject is shown exactly as typed; a name match only links the citizen', function()
    resetObservations()
    local author = handle.ensurePlayer(98)
    readyMdt()
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) and params[1] == 'JJ123456' then return { citizenid = 'JJ123456' } end
    end
    handle.sqlQuery = function(query, params)
        if query:find('LOWER(TRIM(`name`))', 1, true) then
            return params[1]:lower() == 'joe jones' and { { citizenid = 'JJ123456' } } or {}
        end
        return {}
    end
    local create = QB.callback.registry['qbmdt:server:createBolo']
    local function make(kind, identifier)
        local before = #handle.sqlInserts
        local id, err = create(98, { subject_type = kind, identifier = identifier, title = 'Wanted', description = 'Detain.', days = 1 })
        h.assertTrue(id ~= nil, tostring(err))
        local insert = handle.sqlInserts[before + 1]
        h.assertTrue(insert.query:find('`subject_text`', 1, true) ~= nil)
        return insert.params
    end
    local params = make('person', 'Joe Jones')
    h.assertEqual(params[2], 'JJ123456', 'an exact unique name links the citizen')
    h.assertEqual(params[3], 'Joe Jones', 'the subject text is what was typed')
    params = make('person', '  joe jones ')
    h.assertEqual(params[2], 'JJ123456')
    h.assertEqual(params[3], 'joe jones')
    params = make('person', 'JJ123456')
    h.assertEqual(params[2], 'JJ123456')
    h.assertEqual(params[3], 'JJ123456')
    params = make('person', 'Nobody Known')
    h.assertEqual(params[2], 'Nobody Known')
    h.assertEqual(params[3], 'Nobody Known')
    h.assertTrue(params[2] ~= author.citizenid and params[3] ~= author.citizenid, 'the creator is never substituted')
    params = make('vehicle', 'abc 123')
    h.assertEqual(params[2], 'ABC 123')
    h.assertEqual(params[3], 'abc 123')

    local listed
    handle.sqlQuery = function(query)
        listed = query
        return {
            { id = 6, subject_type = 'person', subject_identifier = 'JJ123456', subject_text = 'Joe Jones', linked_name = 'Joe Jones', linked_citizenid = 'JJ123456' },
            { id = 5, subject_type = 'person', subject_identifier = 'JJ123456', legacy_label = 'Joe Jones (JJ123456)', linked_name = 'Joe Jones', linked_citizenid = 'JJ123456' },
            { id = 4, subject_type = 'person', subject_identifier = 'JJ123456', linked_name = 'Joe Jones', linked_citizenid = 'JJ123456' },
            { id = 3, subject_type = 'person', subject_identifier = 'RaVn', legacy_label = 'RaVn' },
            { id = 2, subject_type = 'vehicle', subject_identifier = 'RAVN' },
            { id = 1, subject_type = 'person', subject_identifier = 'GONE1234' },
        }
    end
    local rows = QB.callback.registry['qbmdt:server:bolos'](98)
    h.assertTrue(listed:find('b.`subject_text`', 1, true) ~= nil)
    h.assertTrue(listed:find('CONCAT(', 1, true) == nil, 'the list never builds "Name (CID)"')
    local subjects = {}
    for i, row in ipairs(rows) do subjects[i] = row.subject_label; h.assertEqual(row.legacy_label, nil) end
    h.assertEqual(table.concat(subjects, '|'), 'Joe Jones|Joe Jones|Joe Jones|RaVn|RAVN|GONE1234')
    h.assertEqual(rows[1].linked_citizenid, 'JJ123456')
end)

h.test('warrant and BOLO state changes use server-owned transitions and audit', function()
    resetObservations()
    handle.ensurePlayer(95)
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) then return { citizenid = params[1] } end
    end
    local warrantId = QB.callback.registry['qbmdt:server:createWarrant'](95,
        { citizenid = 'CID000777', reason = 'Signed probable cause', days = 999 })
    h.assertEqual(warrantId, 1)
    h.assertEqual(handle.sqlInserts[1].params[4], Config.mdt.operations.warrantMaxDays)

    local ok = QB.callback.registry['qbmdt:server:closeWarrant'](95, warrantId, 'served')
    h.assertTrue(ok)
    h.assertEqual(handle.sqlUpdates[1].params[1], 'served')
    local invalid, err = QB.callback.registry['qbmdt:server:closeWarrant'](95, warrantId, 'deleted')
    h.assertFalse(invalid)
    h.assertEqual(err, 'invalid warrant action')

    local boloId = QB.callback.registry['qbmdt:server:createBolo'](95, {
        subject_type = 'vehicle', identifier = 'abc 123', title = 'Felony vehicle',
        description = 'Stop and detain occupants.', days = 2,
    })
    h.assertTrue(boloId ~= nil)
    local boloInsert = handle.sqlInserts[#handle.sqlInserts - 1]
    h.assertEqual(boloInsert.params[2], 'ABC 123')
    ok = QB.callback.registry['qbmdt:server:resolveBolo'](95, boloId)
    h.assertTrue(ok)
end)

h.test('weapon licence start enforces distance, existing licence, active state, and inventory failure', function()
    resetObservations()
    handle.ensurePlayer(1, { coords = vector3(0.0, 0.0, 0.0) })
    handle.net('qbmdt:server:startWeaponLicence', 1)
    h.assertEqual(#handle.starts, 0, 'distant player must not reach inventory')

    local licensed = handle.ensurePlayer(2)
    licensed.metadata.licences.weapon = true
    handle.licenceRows[licensed.citizenid] = 'WPN-EXISTING'
    handle.net('qbmdt:server:startWeaponLicence', 2)
    h.assertEqual(#handle.starts, 0, 'licensed player must not start')

    start(3)
    handle.net('qbmdt:server:startWeaponLicence', 3)
    h.assertEqual(#handle.starts, 1, 'an active session must not start twice')
    h.assertEqual(#handle.eventsNamed('qbmdt:client:weaponLicenceStart', 3), 1)

    handle.startTrainingResult = false
    handle.startTrainingError = 'busy'
    start(4)
    handle.startTrainingResult = true
    h.assertEqual(#handle.notifications, 4)
    h.assertEqual(handle.notifications[1].payload.message, 'Move closer to the range marker.')
    h.assertEqual(handle.notifications[2].payload.message, 'You already hold a weapon licence.')
    h.assertEqual(handle.notifications[3].payload.message, 'A range session is already in progress.')
    h.assertEqual(handle.notifications[4].payload.message, 'busy')
    fireRounds(4, 1, Config.mdt.weaponLicence.shots)
    h.assertTrue(latestAuthorization(4) == nil, 'failed start must not create session state')
end)

h.test('weapon licence start accepts the full configured Ammu-Nation interior', function()
    resetObservations()
    local target = Config.mdt.weaponLicence.targetOffsets[#Config.mdt.weaponLicence.targetOffsets]
    local range = Config.mdt.weaponLicence.range
    handle.ensurePlayer(5, { coords = vector3(range.x + target.x, range.y + target.y, range.z + target.z) })
    handle.net('qbmdt:server:startWeaponLicence', 5)
    h.assertEqual(#handle.starts, 1)
end)

h.test('trusted training rounds must have the right owner, weapon, and strict order', function()
    resetObservations()
    start(10)
    handle.event('qbinventory:server:trainingRoundFired', 10,
        { owner = 'attacker', weapon = Config.mdt.weaponLicence.weapon, shot = 1 })
    handle.event('qbinventory:server:trainingRoundFired', 10,
        { owner = 'kora_mdt', weapon = 'weapon_smg', shot = 1 })
    handle.event('qbinventory:server:trainingRoundFired', 10,
        { owner = 'kora_mdt', weapon = Config.mdt.weaponLicence.weapon, shot = 2 })
    h.assertTrue(latestAuthorization(10) == nil)

    fireRounds(10, 1, Config.mdt.weaponLicence.shots - 1)
    h.assertTrue(latestAuthorization(10) == nil, 'qualification must not start early')
    fireRounds(10, Config.mdt.weaponLicence.shots, Config.mdt.weaponLicence.shots)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 10)[1].args[1], true,
        'firing every issued round passes the live-fire test')
    local count = #handle.eventsNamed('qbmdt:client:weaponLicenceResult', 10)
    fireRounds(10, Config.mdt.weaponLicence.shots, Config.mdt.weaponLicence.shots)
    h.assertEqual(#handle.eventsNamed('qbmdt:client:weaponLicenceResult', 10), count, 'the final round may finish only once')
end)

h.test('completing every issued training round issues a licence once', function()
    resetObservations()
    start(20)
    fireRounds(20, 1, Config.mdt.weaponLicence.shots)
    h.assertEqual(handle.sqlWrites, 1)
    h.assertEqual(#handle.metadataWrites, 1)
    h.assertEqual(#handle.stops, 1)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 20)[1].args[1], true)

    fireRounds(20, 1, Config.mdt.weaponLicence.shots)
    h.assertEqual(handle.sqlWrites, 1, 'replayed rounds cannot issue a second licence')
end)

h.test('licence completion reports metadata failure', function()
    resetObservations()
    start(30)
    fireRounds(30, 1, Config.mdt.weaponLicence.shots)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 30)[1].args[1], true)

    -- Metadata is written while the final range round is processed.
    start(32)
    handle.metadataResult = false
    fireRounds(32, 1, Config.mdt.weaponLicence.shots)
    handle.metadataResult = true
    local result = handle.eventsNamed('qbmdt:client:weaponLicenceResult', 32)[1]
    h.assertEqual(result.args[1], false, 'metadata failure must not be reported as success')
end)

h.test('cancel, timeout, drop, and stale timers clean up the correct training session', function()
    resetObservations()
    start(40)
    local oldTimer = handle.timeouts[#handle.timeouts]
    handle.net('qbmdt:server:cancelWeaponLicence', 40)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 40)[1].args[1], false)
    h.assertEqual(#handle.stops, 1)

    handle.net('qbmdt:server:startWeaponLicence', 40)
    oldTimer.callback()
    fireRounds(40, 1, Config.mdt.weaponLicence.shots)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 40)[2].args[1], true,
        'old timer must not clear replacement state')

    start(41)
    handle.timeouts[#handle.timeouts].callback()
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 41)[1].args[1], false)

    start(42)
    handle.event('playerDropped', 42)
    h.assertEqual(#handle.eventsNamed('qbmdt:client:weaponLicenceResult', 42), 0, 'drop cleanup must be silent')
    handle.net('qbmdt:server:startWeaponLicence', 42)
    h.assertEqual(#handle.eventsNamed('qbmdt:client:weaponLicenceStart', 42), 2, 'drop must release active state')
end)

h.test('eligibility changes terminate an active training session', function()
    resetObservations()
    start(50)
    handle.players[50].bucket = 99
    fireRounds(50, 1, 1)
    h.assertEqual(handle.eventsNamed('qbmdt:client:weaponLicenceResult', 50)[1].args[1], false)
    h.assertEqual(#handle.stops, 1)
end)

h.test('analysis start requires on-duty police and the matching evidence bag', function()
    resetObservations()
    handle.ensurePlayer(60, { job = { name = 'ambulance', onduty = true } })
    handle.evidence[60] = 'CASE-60'
    handle.net('qbmdt:server:beginAnalysis', 60, 'CASE-60')

    handle.ensurePlayer(61, { job = { name = 'police', onduty = false } })
    handle.evidence[61] = 'CASE-61'
    handle.net('qbmdt:server:beginAnalysis', 61, 'CASE-61')

    handle.ensurePlayer(62)
    handle.net('qbmdt:server:beginAnalysis', 62, 'CASE-62')
    h.assertEqual(#handle.authorizations, 0)

    handle.ensurePlayer(63)
    handle.evidence[63] = 'CASE-63'
    handle.net('qbmdt:server:beginAnalysis', 63, 'CASE-63')
    handle.net('qbmdt:server:beginAnalysis', 63, 'CASE-63')
    h.assertEqual(#handle.authorizations, 1, 'active analysis must not be replaced')
    local event = handle.eventsNamed('qbmdt:client:analysisStage', 63)[1]
    h.assertEqual(event.args[1], 1)
    h.assertEqual(event.args[2], handle.authorizations[1].token)
end)

h.test('analysis proofs bind every stage and eligibility is rechecked', function()
    resetObservations()
    handle.ensurePlayer(70)
    handle.evidence[70] = 'CASE-70'
    handle.net('qbmdt:server:beginAnalysis', 70, 'CASE-70')
    local authorization = latestAuthorization(70)

    handle.net('qbmdt:server:analysisStage', 70, handle.issueProof(71, authorization.game, authorization.token))
    handle.net('qbmdt:server:analysisStage', 70, handle.issueProof(70, 'circuit', authorization.token))
    handle.net('qbmdt:server:analysisStage', 70, handle.issueProof(70, authorization.game, 'other'))
    h.assertEqual(#handle.eventsNamed('qbmdt:client:analysisStage', 70), 1)

    handle.evidence[70] = nil
    local exact = handle.issueProof(70, authorization.game, authorization.token)
    handle.net('qbmdt:server:analysisStage', 70, exact)
    h.assertEqual(#handle.eventsNamed('qbmdt:client:analysisStage', 70), 1, 'lost evidence must clear instead of advance')

    handle.evidence[70] = 'CASE-70'
    handle.net('qbmdt:server:beginAnalysis', 70, 'CASE-70')
    authorization = latestAuthorization(70)
    handle.players[70].job.onduty = false
    handle.net('qbmdt:server:analysisStage', 70, handle.issueProof(70, authorization.game, authorization.token))
    handle.players[70].job.onduty = true
    handle.net('qbmdt:server:beginAnalysis', 70, 'CASE-70')
    h.assertEqual(#handle.eventsNamed('qbmdt:client:analysisStage', 70), 3, 'role loss must clear and permit a fresh eligible start')
end)

h.test('analysis completes ordered stages and server supplies the pinpad challenge', function()
    resetObservations()
    handle.ensurePlayer(80)
    handle.evidence[80] = 'CASE-80'
    handle.ballisticCasings['CASE-80'] = { weapon_serial = 'SERIAL-80', weapon_name = 'weapon_pistol' }
    handle.net('qbmdt:server:beginAnalysis', 80, 'CASE-80')

    for stage = 1, #Config.mdt.analysis.stages do
        local authorization = latestAuthorization(80)
        h.assertEqual(authorization.game, Config.mdt.analysis.stages[stage].game)
        if authorization.game == 'pinpad' then
            h.assertTrue(type(authorization.opts.numbers) == 'string' and #authorization.opts.numbers == 4)
            h.assertTrue(Config.mdt.analysis.stages[stage].opts.numbers == nil, 'server challenge must not mutate config')
        end
        handle.net('qbmdt:server:analysisStage', 80,
            handle.issueProof(80, authorization.game, authorization.token))
    end

    local result = handle.eventsNamed('qbmdt:client:analysisComplete', 80)[1]
    h.assertEqual(result.args[1].weaponSerial, 'SERIAL-80')
    h.assertEqual(result.args[1].caseId, 'CASE-80')
end)

h.test('analysis cancel, TTL cleanup, and stale timers permit safe retries', function()
    resetObservations()
    handle.ensurePlayer(90)
    handle.evidence[90] = 'CASE-90'
    handle.net('qbmdt:server:beginAnalysis', 90, 'CASE-90')
    local oldTimer = handle.timeouts[#handle.timeouts]
    handle.net('qbmdt:server:cancelAnalysis', 90)
    handle.net('qbmdt:server:beginAnalysis', 90, 'CASE-90')
    oldTimer.callback()

    local authorization = latestAuthorization(90)
    handle.net('qbmdt:server:analysisStage', 90,
        handle.issueProof(90, authorization.game, authorization.token))
    h.assertEqual(handle.eventsNamed('qbmdt:client:analysisStage', 90)[#handle.eventsNamed('qbmdt:client:analysisStage', 90)].args[1], 2,
        'stale timer must not clear replacement analysis')

    handle.net('qbmdt:server:cancelAnalysis', 90)
    handle.net('qbmdt:server:beginAnalysis', 90, 'CASE-90')
    handle.timeouts[#handle.timeouts].callback()
    local startsBefore = #handle.eventsNamed('qbmdt:client:analysisStage', 90)
    handle.net('qbmdt:server:beginAnalysis', 90, 'CASE-90')
    h.assertEqual(#handle.eventsNamed('qbmdt:client:analysisStage', 90), startsBefore + 1, 'TTL cleanup must permit retry')

    handle.event('playerDropped', 90)
    handle.net('qbmdt:server:beginAnalysis', 90, 'CASE-90')
    h.assertEqual(#handle.eventsNamed('qbmdt:client:analysisStage', 90), startsBefore + 2, 'drop cleanup must permit retry')
end)

h.test('formatTime handles number seconds and ms, strings, tables, nil and custom formats on every time key', function()
    resetObservations()
    handle.ensurePlayer(94)
    local saved = Config.mdt.dateFormat
    handle.sqlQuery = function() return { {
        id = 1, updated_at = 1793484969, created_at = 1793484969000, expires_at = '2026-10-31T22:16:09Z',
        closed_at = { year = 2026, month = 1, day = 2, hour = 3, min = 4, sec = 5 }, served_at = 1793484969000,
        issued_at = '1793484969000', date = '2026-10-31 22:16:09', custom_at = { year = 2026, month = 5, day = 6, hour = 7, min = 8 },
        last_updated = nil, opaque_at = { 1, 2, 3 },
    } } end
    local expected = '2026-10-31 22:16'
    local row = QB.callback.registry['qbmdt:server:reports'](94)[1]
    h.assertEqual(row.updated_at, expected)
    h.assertEqual(row.created_at, expected)
    h.assertEqual(row.expires_at, '2026-10-31 22:16')
    h.assertEqual(row.closed_at, '2026-01-02 03:04')
    h.assertEqual(row.served_at, expected)
    h.assertEqual(row.issued_at, expected)
    h.assertEqual(row.date, '2026-10-31 22:16')
    h.assertEqual(row.custom_at, '2026-05-06 07:08', 'any *_at key is formatted')
    h.assertEqual(row.opaque_at, nil, 'an unparseable table is dropped, never passed through')
    Config.mdt.dateFormat = 'DD/MM/YYYY HH:mm:ss'
    row = QB.callback.registry['qbmdt:server:reports'](94)[1]
    Config.mdt.dateFormat = saved
    h.assertEqual(row.expires_at, '31/10/2026 22:16:09')
    h.assertEqual(row.closed_at, '02/01/2026 03:04:05')
    Config.mdt.dateFormat = 'YYYY-MM-DD'
    row = QB.callback.registry['qbmdt:server:reports'](94)[1]
    Config.mdt.dateFormat = saved
    h.assertEqual(row.updated_at, '2026-10-31')
end)

h.test('person profile times (warrants, BOLOs, reports, records) are strings', function()
    resetObservations()
    handle.ensurePlayer(94)
    local when = { year = 2026, month = 10, day = 31, hour = 22, min = 5 }
    _G.json = { decode = function() return {} end }
    handle.sqlSingle = function(query)
        if query:find('FROM `players`', 1, true) then return { citizenid = 'ABC12345', name = 'Jane Doe', charinfo = '{}', metadata = '{}', job = '{}' } end
    end
    handle.sqlQuery = function(query)
        if query:find('qbmdt_warrants', 1, true) then return { { id = 1, reason = 'r', expires_at = when } } end
        if query:find('qbmdt_bolos', 1, true) then return { { id = 1, title = 't', expires_at = 1793484969000 } } end
        if query:find('qbmdt_reports', 1, true) then return { { id = 1, title = 't', status = 'open', created_at = when } } end
        return { { created_at = when, purchased_at = when } }
    end
    local out = QB.callback.registry['qbmdt:server:person'](94, 'ABC12345')
    h.assertEqual(out.warrants[1].expires_at, '2026-10-31 22:05')
    h.assertEqual(out.bolos[1].expires_at, '2026-10-31 22:16')
    h.assertEqual(out.reports[1].created_at, '2026-10-31 22:05')
    h.assertEqual(out.criminal[1].created_at, '2026-10-31 22:05')
    h.assertEqual(out.firearms[1].purchased_at, '2026-10-31 22:05')
end)

h.test('a failing list query returns its reason and is logged instead of an empty list', function()
    resetObservations()
    handle.ensurePlayer(94)
    handle.sqlQuery = function() return nil, 'Illegal mix of collations' end
    for _, name in ipairs({ 'reports', 'cases', 'warrants', 'bolos', 'reportOptions' }) do
        local rows, err = QB.callback.registry['qbmdt:server:' .. name](94)
        h.assertEqual(rows, nil, name .. ' must not turn an error into an empty list')
        h.assertTrue(err:find('Illegal mix of collations', 1, true) ~= nil, name .. ': ' .. tostring(err))
    end
    handle.sqlSingle = function() return { open_reports = 4 } end
    local data, err = QB.callback.registry['qbmdt:server:dashboard'](94)
    h.assertEqual(data, nil)
    h.assertTrue(err:find('Could not load recent reports', 1, true) ~= nil, tostring(err))
    handle.sqlQuery = function() return { { id = 4, title = 't', status = 'open', updated_at = 1793484969000 } } end
    data = QB.callback.registry['qbmdt:server:dashboard'](94)
    h.assertEqual(data.open_reports, 4)
    h.assertEqual(data.recent[1].updated_at, '2026-10-31 22:16')
    handle.sqlSingle = function() return nil, 'no table' end
    data, err = QB.callback.registry['qbmdt:server:dashboard'](94)
    h.assertEqual(data, nil)
    h.assertTrue(err:find('no table', 1, true) ~= nil)
end)

h.test('reports list joins pin collations on charges and players', function()
    resetObservations()
    handle.ensurePlayer(94)
    local seen
    handle.sqlQuery = function(query) seen = query; return {} end
    QB.callback.registry['qbmdt:server:reports'](94)
    h.assertTrue(seen:find('c.`code` COLLATE utf8mb4_unicode_ci = r.`charge_code` COLLATE utf8mb4_unicode_ci', 1, true) ~= nil)
    h.assertTrue(seen:find('p.`citizenid` COLLATE utf8mb4_unicode_ci', 1, true) ~= nil)
end)

h.test('report subject: citizen ID, case-insensitive full name, ambiguous and unknown names', function()
    resetObservations()
    local author = handle.ensurePlayer(99)
    readyMdt()
    local NULL = QB.sql.NULL
    local lookups = {}
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) and params[1] == 'ZZZ99999' then return { citizenid = 'ZZZ99999' } end
    end
    handle.sqlQuery = function(query, params)
        if query:find('LOWER(TRIM(`name`))', 1, true) then
            lookups[#lookups + 1] = { query = query, params = params }
            local name = params[1]:lower()
            if name == 'jane doe' then return { { citizenid = 'JAN00001' } } end
            if name == 'twin one' then return { { citizenid = 'A' }, { citizenid = 'B' } } end
        end
        return {}
    end
    local create = QB.callback.registry['qbmdt:server:createReport']
    local function report(subject)
        local before = #handle.sqlInserts
        local id, err = create(99, { title = 'T', narrative = 'N', citizenid = subject })
        return id, err, handle.sqlInserts[before + 1]
    end
    local id, err, insert = report('ZZZ99999')
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], 'ZZZ99999')
    id, err, insert = report('  JANE   DOE ')
    h.assertTrue(id ~= nil)
    h.assertEqual(insert.params[3], NULL, 'inner whitespace must match exactly, not fuzzily')
    id, err, insert = report('JaNe DoE')
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], 'JAN00001', 'case-insensitive full name links the citizen')
    h.assertTrue(insert.params[3] ~= author.citizenid, 'never defaults to the creator')
    h.assertEqual(insert.params[4], NULL)
    h.assertTrue(lookups[#lookups].query:find('firstname', 1, true) ~= nil and lookups[#lookups].query:find('lastname', 1, true) ~= nil,
        'name lookup uses first + last name')
    id, err = report('Twin One')
    h.assertEqual(id, nil)
    h.assertEqual(err, 'More than one citizen is named "Twin One". Use the citizen ID instead.')
    id, err, insert = report('Nobody Here')
    h.assertTrue(id ~= nil, tostring(err))
    h.assertEqual(insert.params[3], NULL)
    h.assertEqual(insert.params[4], 'Nobody Here', 'unknown name kept as subject_text')
    Config.mdt.reports.allowUnknownSubject = false
    id, err = report('Nobody Here')
    Config.mdt.reports.allowUnknownSubject = true
    h.assertEqual(id, nil)
    h.assertEqual(err, 'Subject must be a citizen ID. No citizen matches "Nobody Here".')
    Config.mdt.reports.resolveSubjectByName = false
    id, err, insert = report('Jane Doe')
    Config.mdt.reports.resolveSubjectByName = true
    h.assertEqual(insert.params[3], NULL, 'name matching can be disabled')
    -- the creator is only the subject when they type their own name or ID
    id, err = report(author.citizenid)
    h.assertEqual(id, nil)
    h.assertEqual(err, 'Citizen ID not found. Check the subject citizen ID.', 'an unknown ID is an error, never swapped for the creator')
end)

h.test('report picker options are bounded by operations.reportOptionsLimit', function()
    resetObservations()
    handle.ensurePlayer(94)
    local seen
    handle.sqlQuery = function(query) seen = query; return {} end
    QB.callback.registry['qbmdt:server:reportOptions'](94)
    h.assertTrue(seen:find('LIMIT 200', 1, true) ~= nil, 'default limit is 200')
    Config.mdt.operations.reportOptionsLimit = 25
    QB.callback.registry['qbmdt:server:reportOptions'](94)
    Config.mdt.operations.reportOptionsLimit = 200
    h.assertTrue(seen:find('LIMIT 25', 1, true) ~= nil, 'limit follows config')
end)

h.report('qbmdt server')
