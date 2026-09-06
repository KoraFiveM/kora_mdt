local C = Config.mdt
local training = {}

local function player(src) return exports.qbcore:getPlayerData(src) end
local function citizenId(src)
    local data = player(src)
    return data and data.citizenid or nil
end
local function role(src)
    local job = exports.qbcore:getJob(src) or {}
    if C.roles.requireOnDuty and job.onduty ~= true then return nil end
    if C.roles.judgeJobs[job.name] then return 'judge' end
    if C.roles.policeJobs[job.name] then return 'police' end
    if C.roles.medicalJobs[job.name] then return 'medical' end
    return nil
end
local function can(src, domain)
    local r = role(src)
    return r == 'judge' or r == domain
end
local function cleanCid(value)
    return type(value) == 'string' and value:match('^[%w%-]+$') and value or nil
end
local function near(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= distance
end
local function licenseNumber(cid)
    local row = QB.sql.single('SELECT `licence_number` FROM `qbmdt_licences` WHERE `citizenid` = ? AND `licence_type` = ?', { cid, 'weapon' })
    return row and row.licence_number or nil
end
local function hasWeaponLicense(src)
    local data = player(src)
    return data and data.metadata and data.metadata.licences and data.metadata.licences.weapon == true and licenseNumber(data.citizenid) ~= nil
end

AddEventHandler('qbmdt:server:databaseReady', function()
    for _, charge in ipairs(C.charges or {}) do
        QB.sql.execute('INSERT IGNORE INTO `qbmdt_charges` (`code`,`label`,`fine`) VALUES (?,?,?)',
            { charge.code, charge.label, math.max(0, math.floor(tonumber(charge.fine) or 0)) })
    end
end)

-- A civilian weapons shop is licence-only. The hook executes before money or
-- stock change, and all fields it uses are server-owned shop/item data.
exports.qbinventory:RegisterHook('buyItem', function(payload, src)
    if payload.shopId ~= C.firearms.shopId then return true end
    if not exports.qbcore:getShared('weapons', payload.itemName) then return true end
    if payload.count ~= 1 or not hasWeaponLicense(src) then return false end
    return true
end)

-- qbinventory generates the weapon serial before it emits this notification.
-- A transfer never re-registers the firearm: this is the original retail
-- purchase record linking its serial, citizen ID, and licence number.
AddEventHandler('qbinventory:server:itemPurchased', function(src, purchase)
    if type(purchase) ~= 'table' or purchase.shopId ~= C.firearms.shopId then return end
    if not exports.qbcore:getShared('weapons', purchase.itemName) then return end
    local cid, serial = citizenId(src), purchase.metadata and purchase.metadata.serial
    local licence = cid and licenseNumber(cid)
    if not cid or type(serial) ~= 'string' or not licence then return end
    CreateThread(function()
        local _, err = QB.sql.execute([[INSERT INTO `qbmdt_firearms`
            (`serial`,`weapon_name`,`owner_citizenid`,`licence_number`,`shop_id`) VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE `owner_citizenid` = VALUES(`owner_citizenid`), `licence_number` = VALUES(`licence_number`)]],
            { serial, purchase.itemName, cid, licence, C.firearms.shopId })
        if err then print(('^1[qbmdt]^7 firearm registration failed: %s'):format(tostring(err))) end
    end)
end)

QB.callback.register('qbmdt:server:person', function(src, wanted)
    wanted = cleanCid(wanted)
    local r = role(src)
    if not wanted or not r then return nil, 'not authorised' end
    local identity = QB.sql.single('SELECT `citizenid`,`name`,`metadata` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { wanted })
    if not identity then return nil, 'person not found' end
    local metadata = type(identity.metadata) == 'string' and json.decode(identity.metadata) or (identity.metadata or {})
    local out = { citizenid = identity.citizenid, name = identity.name, driverLicensed = metadata.licences and metadata.licences.driver == true }
    if r == 'police' or r == 'judge' then
        out.weaponLicence = licenseNumber(wanted)
        out.firearms = QB.sql.query('SELECT `serial`,`weapon_name`,`purchased_at` FROM `qbmdt_firearms` WHERE `owner_citizenid` = ? ORDER BY `purchased_at` DESC', { wanted }) or {}
        out.criminal = QB.sql.query('SELECT `charge_code`,`notes`,`created_at` FROM `qbmdt_criminal_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
    end
    if r == 'medical' or r == 'judge' then
        out.medical = QB.sql.query('SELECT `notes`,`created_at` FROM `qbmdt_medical_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
    end
    return out
end)

QB.callback.register('qbmdt:server:vehicle', function(src, plate)
    if not can(src, 'police') then return nil, 'not authorised' end
    plate = type(plate) == 'string' and plate:gsub('^%s+', ''):gsub('%s+$', ''):upper() or ''
    if plate == '' or #plate > 8 then return nil, 'invalid plate' end
    return QB.sql.single('SELECT `plate`,`model`,`citizenid`,`state`,`garage_id`,`impound_lot` FROM `player_vehicles` WHERE `plate` = ? AND `deleted_at` IS NULL', { plate })
end)

QB.callback.register('qbmdt:server:charges', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.query('SELECT `code`,`label`,`fine` FROM `qbmdt_charges` WHERE `active` = 1 ORDER BY `code`') or {}
end)

QB.callback.register('qbmdt:server:addCriminal', function(src, wanted, code, notes)
    if not can(src, 'police') then return false, 'not authorised' end
    wanted, code = cleanCid(wanted), type(code) == 'string' and code:upper() or nil
    local author = citizenId(src)
    if not wanted or not code or not author then return false, 'invalid record' end
    local charge = QB.sql.single('SELECT `code` FROM `qbmdt_charges` WHERE `code` = ? AND `active` = 1', { code })
    if not charge then return false, 'unknown charge' end
    return QB.sql.execute('INSERT INTO `qbmdt_criminal_records` (`citizenid`,`charge_code`,`notes`,`author_citizenid`) VALUES (?,?,?,?)',
        { wanted, code, tostring(notes or ''):sub(1, 1000), author })
end)

QB.callback.register('qbmdt:server:addMedical', function(src, wanted, notes)
    if not can(src, 'medical') then return false, 'not authorised' end
    wanted = cleanCid(wanted)
    local author = citizenId(src)
    if not wanted or not author or type(notes) ~= 'string' or notes == '' then return false, 'invalid record' end
    return QB.sql.execute('INSERT INTO `qbmdt_medical_records` (`citizenid`,`notes`,`author_citizenid`) VALUES (?,?,?)',
        { wanted, notes:sub(1, 1000), author })
end)

QB.callback.register('qbmdt:server:shopFirearm', function(src, serial)
    serial = type(serial) == 'string' and serial:upper():sub(1, 96) or ''
    if serial == '' then return nil, 'serial is required' end
    if C.firearms.lookupMode ~= 'mdt' then
        local validCounter = false
        for _, counter in ipairs(C.firearms.shopRecords) do if near(src, counter.coords, 2.0) then validCounter = true; break end end
        if not validCounter then return nil, 'speak to the store records clerk' end
    elseif not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.single('SELECT `serial`,`weapon_name`,`owner_citizenid`,`licence_number`,`purchased_at` FROM `qbmdt_firearms` WHERE `serial` = ?', { serial })
end)

-- Three-stage analysis is driven by qblib proofs. The client cannot claim a
-- pass: each stage consumes the one-use server proof generated by qblib.
local analysis = {}
local function hasEvidenceCase(src, caseId)
    local bags = exports.qbinventory:GetItemsByName(src, 'filled_evidence_bag') or {}
    for _, bag in pairs(bags) do
        if bag.info and bag.info.caseId == caseId then return true end
    end
    return false
end

local function authorizeAnalysisStage(src, stage)
    local definition = C.analysis.stages[stage]
    if not definition then return nil end
    local opts = {}
    for key, value in pairs(definition.opts or {}) do opts[key] = value end
    if definition.game == 'pinpad' then opts.numbers = tostring(math.random(1000, 9999)) end
    return QB.minigames.authorizeProof(src, definition.game, opts)
end

QB.events.register('qbmdt:server:open', function(src)
    local userRole = role(src)
    if userRole then TriggerClientEvent('qbmdt:client:open', src, userRole) end
end, { rateLimit = { max = 4, window = 2000 } })
QB.events.register('qbmdt:server:beginAnalysis', function(src, caseId)
    if not can(src, 'police') or type(caseId) ~= 'string' then return end
    local existing = analysis[src]
    if existing and existing.expiresAt < GetGameTimer() then analysis[src] = nil; existing = nil end
    if existing or not hasEvidenceCase(src, caseId) then return end

    local authorization = authorizeAnalysisStage(src, 1)
    if not authorization then return end
    analysis[src] = {
        caseId = caseId,
        stage = 1,
        authorization = authorization,
        expiresAt = GetGameTimer() + C.analysis.ttl,
    }
    local state = analysis[src]
    SetTimeout(C.analysis.ttl + 1, function()
        if analysis[src] == state then analysis[src] = nil end
    end)
    TriggerClientEvent('qbmdt:client:analysisStage', src, 1, authorization)
end, { rateLimit = { max = 2, window = 3000 } })
QB.events.register('qbmdt:server:cancelAnalysis', function(src)
    analysis[src] = nil
end, { rateLimit = { max = 4, window = 3000 } })
QB.events.register('qbmdt:server:analysisStage', function(src, token)
    local state = analysis[src]
    if not state or type(token) ~= 'string' then return end
    if state.expiresAt < GetGameTimer() or not can(src, 'police')
        or not hasEvidenceCase(src, state.caseId) then analysis[src] = nil; return end

    local definition = C.analysis.stages[state.stage]
    if not definition or not QB.minigames.consumeProof(src, token,
        definition.game, state.authorization) then return end

    state.stage = state.stage + 1
    if state.stage <= #C.analysis.stages then
        state.authorization = authorizeAnalysisStage(src, state.stage)
        if not state.authorization then analysis[src] = nil; return end
        return TriggerClientEvent('qbmdt:client:analysisStage', src, state.stage, state.authorization)
    end
    local row = exports.qbpolice:GetBallisticCasing(state.caseId)
    analysis[src] = nil
    if row then TriggerClientEvent('qbmdt:client:analysisComplete', src, { caseId = state.caseId, weaponSerial = row.weapon_serial, weapon = row.weapon_name }) end
end, { rateLimit = { max = 5, window = 5000 } })

local function issueWeaponLicence(src, state)
    local cid = citizenId(src)
    if cid ~= state.citizenid or hasWeaponLicense(src) then return false end

    local number = ('WPN-%s-%04d'):format(cid:sub(-6):upper(), math.random(0, 9999))
    local written = QB.sql.execute([[INSERT INTO `qbmdt_licences`
        (`citizenid`,`licence_type`,`licence_number`) VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE `licence_number` = VALUES(`licence_number`)]], { cid, 'weapon', number })
    if not written then return false end

    local data = player(src)
    if not data then return false end
    local licences = {}
    for key, value in pairs((data.metadata and data.metadata.licences) or {}) do
        licences[key] = value
    end
    licences.weapon = true
    return exports.qbcore:setMetaData(src, 'licences', licences) == true
end

local function finishTraining(src, state, passed, silent)
    if training[src] ~= state or state.finishing then return end
    state.finishing = true
    exports.qbinventory:StopTrainingWeapon(src)

    passed = passed == true and issueWeaponLicence(src, state)
    if training[src] == state then training[src] = nil end
    if not silent then TriggerClientEvent('qbmdt:client:weaponLicenceResult', src, passed == true, state.shots) end
end

local function stillEligible(src, state)
    return state.expiresAt >= GetGameTimer()
        and state.citizenid == citizenId(src)
        and state.bucket == GetPlayerRoutingBucket(src)
        and near(src, C.weaponLicence.range, C.weaponLicence.interactionDistance + 3.0)
end

local function beginQualification(src, state)
    if training[src] ~= state or state.authorization then return end
    local definition = C.weaponLicence.qualification
    local authorization = QB.minigames.authorizeProof(src, definition.game, definition.opts)
    if not authorization then return finishTraining(src, state, false) end
    state.authorization = authorization
    TriggerClientEvent('qbmdt:client:weaponLicenceQualification', src, authorization)
end

QB.events.register('qbmdt:server:startWeaponLicence', function(src)
    if training[src] or not near(src, C.weaponLicence.range, C.weaponLicence.interactionDistance) then return end

    local cid = citizenId(src)
    local bucket = GetPlayerRoutingBucket(src)
    if not cid or hasWeaponLicense(src) then return end

    local current = GetGameTimer()
    local state = {
        citizenid = cid,
        shots = 0,
        bucket = bucket,
        expiresAt = current + C.weaponLicence.trainingTimeout,
    }
    local started, startErr = exports.qbinventory:StartTrainingWeapon(src, C.weaponLicence.weapon, C.weaponLicence.shots)
    if not started then
        return QB.notify.send(src, { title = 'Weapon licence', message = startErr or 'The range is unavailable.', type = 'error' })
    end

    training[src] = state
    TriggerClientEvent('qbmdt:client:weaponLicenceStart', src, {
        targetModel = C.weaponLicence.targetModel,
        targetHeading = C.weaponLicence.targetHeading,
        range = C.weaponLicence.range,
        targetOffsets = C.weaponLicence.targetOffsets,
        shots = C.weaponLicence.shots,
    })
    SetTimeout(C.weaponLicence.trainingTimeout, function()
        if training[src] == state then finishTraining(src, state, false) end
    end)
end, { rateLimit = { max = 1, window = 2000 } })

AddEventHandler('qbinventory:server:trainingRoundFired', function(src, round)
    local state = training[src]
    if not state or type(round) ~= 'table' or round.owner ~= GetCurrentResourceName()
        or round.weapon ~= C.weaponLicence.weapon or round.shot ~= state.shots + 1 then return end
    if not stillEligible(src, state) then return finishTraining(src, state, false) end

    state.shots = round.shot
    if state.shots >= C.weaponLicence.shots then beginQualification(src, state) end
end)

QB.events.register('qbmdt:server:completeWeaponLicence', function(src, proof)
    local state = training[src]
    local definition = C.weaponLicence.qualification
    if not state or state.shots < C.weaponLicence.shots or type(proof) ~= 'string'
        or not stillEligible(src, state) or not state.authorization then return end
    if not QB.minigames.consumeProof(src, proof, definition.game, state.authorization) then return end
    finishTraining(src, state, true)
end, { rateLimit = { max = 3, window = 5000 } })

QB.events.register('qbmdt:server:cancelWeaponLicence', function(src)
    local state = training[src]
    if state then finishTraining(src, state, false) end
end, { rateLimit = { max = 3, window = 5000 } })

AddEventHandler('playerDropped', function()
    local src, state = source, training[source]
    if state then finishTraining(src, state, false, true) end
    analysis[src] = nil
end)
