local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install()
dofile('config.lua')
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

h.test('incident reports validate server records, create charge history, and audit', function()
    resetObservations()
    handle.ensurePlayer(94)
    handle.sqlSingle = function(query, params)
        if query:find('FROM `players`', 1, true) then return { citizenid = params[1] } end
        if query:find('FROM `qbmdt_charges`', 1, true) and params[1] == 'SPD-01' then return { code = 'SPD-01' } end
    end
    local create = QB.callback.registry['qbmdt:server:createReport']
    local id, err = create(94, { title = 'Traffic stop', narrative = 'Vehicle failed to stop.', citizenid = 'CID000777', charge = 'bad' })
    h.assertEqual(id, nil)
    h.assertEqual(err, 'unknown charge')

    id, err = create(94, { title = 'Traffic stop', narrative = 'Vehicle failed to stop.', citizenid = 'CID000777', charge = 'spd-01' })
    h.assertEqual(id, 1)
    h.assertEqual(handle.sqlInserts[1].params[4], 'SPD-01')
    h.assertTrue(handle.sqlInserts[2].query:find('qbmdt_criminal_records', 1, true) ~= nil,
        'charged report must be reflected in criminal history')
    h.assertTrue(handle.sqlInserts[3].query:find('qbmdt_audit_log', 1, true) ~= nil,
        'report creation must be audited')
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

h.report('qbmdt server')
