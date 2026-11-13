local C = Config.mdt
local training = {}
local databaseReady = false
local chargeCache = {}

local function player(src) return exports.kora_core:getPlayerData(src) end
local function citizenId(src)
    local data = player(src)
    return data and data.citizenid or nil
end
local function role(src)
    local job = exports.kora_core:getJob(src) or {}
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
local function isPoliceBoss(src)
    local job = exports.kora_core:getJob(src) or {}
    return C.roles.policeJobs[job.name] == true
        and (not C.roles.requireOnDuty or job.onduty == true)
        and (job.isboss == true or (type(job.grade) == 'table' and job.grade.isboss == true))
end
local function cleanCid(value)
    return type(value) == 'string' and value:match('^[%w%-]+$') and value or nil
end
local function cleanText(value, maximum, required)
    if type(value) ~= 'string' then return required and nil or '' end
    value = value:gsub('[%z\1-\8\11\12\14-\31]', ''):match('^%s*(.-)%s*$')
    if value == '' and required then return nil end
    return value:sub(1, maximum)
end
-- Names the first required (per Config.mdt.requiredFields) field that is empty.
local function missingRequired(form, order, values)
    local present = {}
    for field, value in pairs(values) do present[field] = value ~= nil and value ~= '' end
    return MdtRequired.firstMissing(form, order, present)
end
local function cleanId(value)
    local id = math.floor(tonumber(value) or 0)
    return id > 0 and id or nil
end
local function likeTerm(value)
    value = cleanText(value, 64, true)
    if not value or #value < 2 then return nil end
    return value
end
local function personExists(cid)
    return cid and Kora.sql.single('SELECT `citizenid` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { cid }) ~= nil
end
local function logError(where, err)
    print(('^1[kora_mdt]^7 %s: %s'):format(where, tostring(err)))
end
-- Exact, case-insensitive full-name lookup. Returns the citizen ID of a single match,
-- nil for no match, or nil plus true when several citizens share the name.
local function resolvePersonByName(name)
    name = cleanText(name, 128, false)
    if name == '' then return nil end
    local rows = Kora.sql.query([[SELECT `citizenid` FROM `players` WHERE `deleted_at` IS NULL AND (LOWER(TRIM(`name`)) = LOWER(?)
        OR LOWER(IF(JSON_VALID(`charinfo`), CONCAT(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.firstname'))), ''), ' ',
            NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(`charinfo`, '$.lastname'))), '')), NULL)) = LOWER(?)) LIMIT 2]], { name, name }) or {}
    if #rows == 1 then return rows[1].citizenid end
    if #rows > 1 then return nil, true end
    return nil
end
-- Everything the terminal shows as a time goes through formatTime so the NUI
-- only receives plain strings; raw TIMESTAMP columns can arrive as tables.
local TIME_KEYS = { created_at = true, updated_at = true, expires_at = true, purchased_at = true, last_updated = true,
    closed_at = true, served_at = true, issued_at = true, date = true, timestamp = true }
-- Any column named *_at is a time too, so a new column can never leak a raw table to the NUI.
local function isTimeKey(key) return TIME_KEYS[key] == true or (type(key) == 'string' and key:sub(-3) == '_at') end
local function ts(column) return 'CAST(' .. column .. ' AS CHAR)' end
local function formatTime(value)
    local y, mo, d, h, mi, se
    if type(value) == 'string' and value:match('^%d+$') and #value >= 9 then value = tonumber(value) end
    if type(value) == 'number' then
        local t = os.date('!*t', math.floor(value > 1e11 and value / 1000 or value))
        y, mo, d, h, mi, se = t.year, t.month, t.day, t.hour, t.min, t.sec
    elseif type(value) == 'string' then
        y, mo, d, h, mi, se = value:match('^(%d%d%d%d)-(%d%d)-(%d%d)[T ]?(%d*):?(%d*):?(%d*)')
    elseif type(value) == 'table' and value.year then
        y, mo, d, h, mi, se = value.year, value.month, value.day, value.hour, value.min or value.minute, value.sec or value.second
    end
    if not y then return nil end
    local parts = { YYYY = y, MM = mo, DD = d, HH = h, mm = mi, ss = se }
    return (tostring(C.dateFormat or 'YYYY-MM-DD HH:mm'):gsub('%a+', function(token)
        if parts[token] == nil then return token end
        return Kora.lang('Error.value_02d', tonumber(parts[token]) or 0)
    end))
end
local function withTimes(data)
    if type(data) ~= 'table' then return data end
    for key, value in pairs(data) do
        if isTimeKey(key) then data[key] = formatTime(value)
        elseif type(value) == 'table' then withTimes(value) end
    end
    return data
end
-- Runs a list query. A failure is logged and returned with its reason; callers must not
-- turn it into an empty list, or a broken query reads as "No reports found."
local function listQuery(what, sql, params)
    local rows, err = Kora.sql.query(sql, params)
    if not rows then
        logError(what .. ' query failed', err)
        return nil, Kora.lang('Error.could_not_load', what, cleanText(tostring(err or Kora.lang('Error.database_query_failed')), 200, false))
    end
    return withTimes(rows)
end
local function audit(src, action, targetType, targetId, details)
    local actor = citizenId(src)
    if not actor then return end
    Kora.sql.insert([[INSERT INTO `kora_mdt_audit_log`
        (`actor_citizenid`,`action`,`target_type`,`target_id`,`details`) VALUES (?,?,?,?,?)]],
        { actor, action, targetType, tostring(targetId), cleanText(details, 1000, false) })
end
local function near(src, coords, distance)
    return Kora.distance.player(src, vector3(coords.x, coords.y, coords.z), distance)
end
local function weaponLicenceZoneHeight()
    local zone, lowest = C.weaponLicence.zone, math.huge
    for _, point in ipairs(zone.points) do lowest = math.min(lowest, point.z) end
    return lowest, lowest + zone.thickness
end
local function pointInWeaponLicenceZone(coords, padding)
    local zone = C.weaponLicence.zone
    padding = padding or 0.0
    local minZ, maxZ = weaponLicenceZoneHeight()
    if coords.z < minZ - padding or coords.z > maxZ + padding then return false end

    local inside, previous = false, zone.points[#zone.points]
    for _, point in ipairs(zone.points) do
        if (point.y > coords.y) ~= (previous.y > coords.y)
            and coords.x < (previous.x - point.x) * (coords.y - point.y) / (previous.y - point.y) + point.x then
            inside = not inside
        end
        previous = point
    end
    if inside or padding == 0 then return inside end

    local paddingSq = padding * padding
    previous = zone.points[#zone.points]
    for _, point in ipairs(zone.points) do
        local dx, dy = point.x - previous.x, point.y - previous.y
        local lengthSq = dx * dx + dy * dy
        local t = lengthSq > 0 and math.max(0, math.min(1, ((coords.x - previous.x) * dx + (coords.y - previous.y) * dy) / lengthSq)) or 0
        local nearestX, nearestY = previous.x + t * dx, previous.y + t * dy
        local nearX, nearY = coords.x - nearestX, coords.y - nearestY
        if nearX * nearX + nearY * nearY <= paddingSq then return true end
        previous = point
    end
    return false
end
local function nearWeaponLicenceZone(src, padding)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and pointInWeaponLicenceZone(GetEntityCoords(ped), padding)
end
local function licenseNumber(cid)
    local row = Kora.sql.single('SELECT `licence_number` FROM `kora_mdt_licences` WHERE `citizenid` = ? AND `licence_type` = ?', { cid, 'weapon' })
    return row and row.licence_number or nil
end
local function hasWeaponLicense(src)
    local data = player(src)
    return data and data.metadata and data.metadata.licences and data.metadata.licences.weapon == true and licenseNumber(data.citizenid) ~= nil
end

AddEventHandler('kora_mdt:server:databaseReady', function()
    for _, charge in ipairs(C.charges or {}) do
        local _, err = Kora.sql.execute('INSERT IGNORE INTO `kora_mdt_charges` (`code`,`label`,`fine`) VALUES (?,?,?)',
            { charge.code, charge.label, math.max(0, math.floor(tonumber(charge.fine) or 0)) })
        if err then
            print(('^1[kora_mdt]^7 charge seed failed for %s: %s'):format(charge.code, tostring(err)))
            return
        end
    end
    local rows, err = Kora.sql.query('SELECT `code`,`label`,`fine` FROM `kora_mdt_charges` WHERE `active` = 1 ORDER BY `label`,`code`')
    if not rows then
        print(('^1[kora_mdt]^7 charge cache load failed: %s'):format(tostring(err or 'database query failed')))
        return
    end
    chargeCache = rows
    databaseReady = true
end)

-- A civilian weapons shop is licence-only. The hook executes before money or
-- stock change, and all fields it uses are server-owned shop/item data.
exports.kora_inventory:RegisterHook('buyItem', function(payload, src)
    if payload.shopId ~= C.firearms.shopId then return true end
    if not exports.kora_core:getShared('weapons', payload.itemName) then return true end
    if payload.count ~= 1 then return false end
    if not hasWeaponLicense(src) then return 'You need a weapon licence to purchase firearms.' end
    return true
end)

-- kora_inventory generates the weapon serial before it emits this notification.
-- A transfer never re-registers the firearm: this is the original retail
-- purchase record linking its serial, citizen ID, and licence number.
AddEventHandler('kora_inventory:server:itemPurchased', function(src, purchase)
    if type(purchase) ~= 'table' or purchase.shopId ~= C.firearms.shopId then return end
    if not exports.kora_core:getShared('weapons', purchase.itemName) then return end
    local cid, serial = citizenId(src), purchase.metadata and purchase.metadata.serial
    local licence = cid and licenseNumber(cid)
    if not cid or type(serial) ~= 'string' or not licence then return end
    CreateThread(function()
        local _, err = Kora.sql.execute([[INSERT INTO `kora_mdt_firearms`
            (`serial`,`weapon_name`,`owner_citizenid`,`licence_number`,`shop_id`) VALUES (?,?,?,?,?)
            ON DUPLICATE KEY UPDATE `owner_citizenid` = VALUES(`owner_citizenid`), `licence_number` = VALUES(`licence_number`)]],
            { serial, purchase.itemName, cid, licence, C.firearms.shopId })
        if err then print(('^1[kora_mdt]^7 firearm registration failed: %s'):format(tostring(err))) end
    end)
end)

Kora.callback.register('kora_mdt:server:person', function(src, wanted)
    wanted = cleanCid(wanted)
    local r = role(src)
    if not wanted or not r then return nil, Kora.lang('Error.not_authorised') end
    local identity = Kora.sql.single('SELECT `citizenid`,`name`,`phone_number`,`charinfo`,`job`,`metadata` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { wanted })
    if not identity then return nil, Kora.lang('Error.person_not_found') end
    local metadata = type(identity.metadata) == 'string' and json.decode(identity.metadata) or (identity.metadata or {})
    local charinfo = type(identity.charinfo) == 'string' and json.decode(identity.charinfo) or (identity.charinfo or {})
    local job = type(identity.job) == 'string' and json.decode(identity.job) or (identity.job or {})
    local out = {
        citizenid = identity.citizenid,
        name = identity.name,
        phone = identity.phone_number or charinfo.phone,
        birthdate = charinfo.birthdate,
        gender = charinfo.gender,
        nationality = charinfo.nationality,
        job = job.label or job.name,
        driverLicensed = metadata.licences and metadata.licences.driver == true,
    }
    if r == 'police' or r == 'judge' then
        out.weaponLicence = licenseNumber(wanted)
        out.firearms = Kora.sql.query('SELECT `serial`,`weapon_name`,' .. ts('`purchased_at`') .. ' AS `purchased_at` FROM `kora_mdt_firearms` WHERE `owner_citizenid` = ? ORDER BY `purchased_at` DESC', { wanted }) or {}
        out.criminal = Kora.sql.query('SELECT `charge_code`,`notes`,' .. ts('`created_at`') .. ' AS `created_at` FROM `kora_mdt_criminal_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
        out.reports = Kora.sql.query([[SELECT `id`,`title`,`status`,]] .. ts('`created_at`') .. [[ AS `created_at` FROM `kora_mdt_reports`
            WHERE `subject_citizenid` = ? ORDER BY `created_at` DESC LIMIT 25]], { wanted }) or {}
        out.warrants = Kora.sql.query([[SELECT `id`,`reason`,`expires_at` FROM `kora_mdt_warrants`
            WHERE `citizenid` = ? AND `status` = 'active' AND `expires_at` > NOW() ORDER BY `expires_at`]], { wanted }) or {}
        out.bolos = Kora.sql.query([[SELECT `id`,`title`,`description`,`expires_at` FROM `kora_mdt_bolos`
            WHERE `subject_type` = 'person' AND `subject_identifier` = ? AND `status` = 'active'
            AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC]], { wanted }) or {}
    end
    if r == 'medical' or r == 'judge' then
        out.medical = Kora.sql.query('SELECT `notes`,' .. ts('`created_at`') .. ' AS `created_at` FROM `kora_mdt_medical_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
    end
    return withTimes(out)
end)

Kora.callback.register('kora_mdt:server:vehicle', function(src, plate)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    plate = type(plate) == 'string' and plate:gsub('^%s+', ''):gsub('%s+$', ''):upper() or ''
    if plate == '' or #plate > 15 then return nil, Kora.lang('Error.invalid_plate') end
    local vehicle = Kora.sql.single([[SELECT v.`plate`,v.`model`,v.`citizenid`,v.`state`,v.`garage_id`,v.`impound_lot`,p.`name` AS `owner_name`
        FROM `player_vehicles` v LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = v.`citizenid` COLLATE utf8mb4_unicode_ci
        WHERE v.`plate` = ? AND v.`deleted_at` IS NULL]], { plate })
    if vehicle then
        vehicle.bolos = Kora.sql.query([[SELECT `id`,`title`,`description`,`expires_at` FROM `kora_mdt_bolos`
            WHERE `subject_type` = 'vehicle' AND `subject_identifier` = ? AND `status` = 'active'
            AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC]], { plate }) or {}
    end
    return vehicle
end)

Kora.callback.register('kora_mdt:server:charges', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    if not databaseReady then return nil, Kora.lang('Error.mdt_database_is_still_starting') end
    return chargeCache
end)

Kora.callback.register('kora_mdt:server:canManageCharges', function(src)
    return isPoliceBoss(src)
end)

Kora.callback.register('kora_mdt:server:manageCharges', function(src)
    if not isPoliceBoss(src) then return nil, Kora.lang('Error.not_authorised') end
    if not databaseReady then return nil, Kora.lang('Error.mdt_database_is_still_starting') end
    return Kora.sql.query('SELECT `code`,`label`,`fine`,`active` FROM `kora_mdt_charges` ORDER BY `label`,`code`')
end)

Kora.callback.register('kora_mdt:server:createCharge', function(src, input)
    if not isPoliceBoss(src) then return false, Kora.lang('Error.not_authorised') end
    if not databaseReady or type(input) ~= 'table' then return false, Kora.lang('Error.invalid_charge') end
    local code = cleanText(input.code, 32, true)
    local label = cleanText(input.label, 128, true)
    local fine = tonumber(input.fine)
    if not code or not code:match('^[%w_%-]+$') or not label or not fine or fine < 0 or fine > 2000000000 then
        return false, Kora.lang('Error.enter_a_valid_code_label')
    end
    code = code:upper()
    local _, err = Kora.sql.execute('INSERT INTO `kora_mdt_charges` (`code`,`label`,`fine`,`active`) VALUES (?,?,?,1)',
        { code, label, math.floor(fine) })
    if err then return false, Kora.lang('Error.could_not_save_charge_the') end
    chargeCache = Kora.sql.query('SELECT `code`,`label`,`fine` FROM `kora_mdt_charges` WHERE `active` = 1 ORDER BY `label`,`code`') or chargeCache
    audit(src, 'charge.create', 'charge', code, label)
    return true
end)

Kora.callback.register('kora_mdt:server:updateCharge', function(src, code, label, fine)
    if not isPoliceBoss(src) then return false, Kora.lang('Error.not_authorised') end
    code = cleanText(code, 32, true)
    label = cleanText(label, 128, true)
    fine = tonumber(fine)
    if not databaseReady or not code or not code:match('^[%w_%-]+$') or not label
        or not fine or fine < 0 or fine > 2000000000 then
        return false, Kora.lang('Error.enter_a_valid_charge_name')
    end
    code = code:upper()
    if not Kora.sql.single('SELECT `code` FROM `kora_mdt_charges` WHERE `code` = ?', { code }) then
        return false, Kora.lang('Error.charge_not_found')
    end
    local updated, err = Kora.sql.execute('UPDATE `kora_mdt_charges` SET `label` = ?, `fine` = ? WHERE `code` = ?',
        { label, math.floor(fine), code })
    if err or updated == false then return false, err or Kora.lang('Error.could_not_update_charge') end
    chargeCache = Kora.sql.query('SELECT `code`,`label`,`fine` FROM `kora_mdt_charges` WHERE `active` = 1 ORDER BY `label`,`code`') or chargeCache
    audit(src, 'charge.update', 'charge', code, label)
    return true
end)

Kora.callback.register('kora_mdt:server:addCriminal', function(src, wanted, code, notes)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    wanted = cleanCid(wanted)
    local selection = cleanText(code, 128, false)
    local author = citizenId(src)
    notes = cleanText(notes, 1000, false)
    local missing = missingRequired('criminal', { 'citizenid', 'charge', 'notes' },
        { citizenid = wanted, charge = selection, notes = notes })
    if missing then return false, missing end
    if not author then return false, Kora.lang('Error.author_unavailable') end
    local charge = Kora.sql.single('SELECT `code` FROM `kora_mdt_charges` WHERE `active` = 1 AND (`code` = ? OR `label` = ?)',
        { selection:upper(), selection })
    if not charge then return false, Kora.lang('Error.unknown_charge') end
    if not personExists(wanted) then return false, Kora.lang('Error.citizen_not_found') end
    local written, err = Kora.sql.execute('INSERT INTO `kora_mdt_criminal_records` (`citizenid`,`charge_code`,`notes`,`author_citizenid`) VALUES (?,?,?,?)',
        { wanted, charge.code, notes, author })
    if not written then return false, err or Kora.lang('Error.database_error') end
    audit(src, 'criminal.create', 'citizen', wanted, code)
    return true
end)

Kora.callback.register('kora_mdt:server:addMedical', function(src, wanted, notes)
    if not can(src, 'medical') then return false, Kora.lang('Error.not_authorised') end
    wanted = cleanCid(wanted)
    local author = citizenId(src)
    notes = cleanText(notes, 1000, false)
    local missing = missingRequired('medical', { 'citizenid', 'notes' }, { citizenid = wanted, notes = notes })
    if missing then return false, missing end
    if not author then return false, Kora.lang('Error.author_unavailable') end
    if not personExists(wanted) then return false, Kora.lang('Error.citizen_not_found') end
    local written, err = Kora.sql.execute('INSERT INTO `kora_mdt_medical_records` (`citizenid`,`notes`,`author_citizenid`) VALUES (?,?,?)',
        { wanted, notes, author })
    if not written then return false, err or Kora.lang('Error.database_error') end
    audit(src, 'medical.create', 'citizen', wanted)
    return true
end)

Kora.callback.register('kora_mdt:server:shopFirearm', function(src, serial)
    serial = type(serial) == 'string' and serial:upper():sub(1, 96) or ''
    if serial == '' then return nil, Kora.lang('Error.serial_is_required') end
    if C.firearms.lookupMode ~= 'mdt' then
        local validCounter = false
        for _, counter in ipairs(C.firearms.shopRecords) do if near(src, counter.coords, 2.0) then validCounter = true; break end end
        if not validCounter then return nil, Kora.lang('Error.speak_to_the_store_records') end
    elseif not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    return Kora.sql.single('SELECT `serial`,`weapon_name`,`owner_citizenid`,`licence_number`,`purchased_at` FROM `kora_mdt_firearms` WHERE `serial` = ?', { serial })
end)

-- Operational MDT data. These callbacks deliberately keep search limits and
-- all mutations on the server; the AppShell is a presentation layer, not an
-- authority boundary.
Kora.callback.register('kora_mdt:server:dashboard', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    local counts, countErr = Kora.sql.single([[SELECT
        (SELECT COUNT(*) FROM `kora_mdt_reports` WHERE `status` = 'open') AS `open_reports`,
        (SELECT COUNT(*) FROM `kora_mdt_cases` WHERE `status` <> 'closed') AS `open_cases`,
        (SELECT COUNT(*) FROM `kora_mdt_warrants` WHERE `status` = 'active' AND `expires_at` > NOW()) AS `active_warrants`,
        (SELECT COUNT(*) FROM `kora_mdt_bolos` WHERE `status` = 'active' AND (`expires_at` IS NULL OR `expires_at` > NOW())) AS `active_bolos`]])
    if not counts then
        logError('dashboard counts query failed', countErr)
        return nil, Kora.lang('Error.could_not_load_the_dashboard', cleanText(tostring(countErr or Kora.lang('Error.database_query_failed')), 200, false))
    end
    local recent, recentErr = listQuery('recent reports', [[SELECT `id`,`title`,`status`,`author_citizenid`,]] .. ts('`updated_at`') .. [[ AS `updated_at`
        FROM `kora_mdt_reports` ORDER BY `updated_at` DESC, `id` DESC LIMIT 8]])
    if not recent then return nil, recentErr end
    counts.recent = recent
    return counts
end)

Kora.callback.register('kora_mdt:server:searchPeople', function(src, query)
    if not role(src) then return nil, Kora.lang('Error.not_authorised') end
    local term = likeTerm(query)
    if not term then return nil, Kora.lang('Error.enter_at_least_two_characters') end
    return withTimes(Kora.sql.query(([[SELECT `citizenid`,`name`,`phone_number`,`last_updated`
        FROM `players` WHERE `deleted_at` IS NULL
        AND (LOCATE(?,`citizenid`) > 0 OR LOCATE(?,`name`) > 0 OR LOCATE(?,COALESCE(`phone_number`,'')) > 0)
        ORDER BY `name` LIMIT %d]]):format(C.operations.searchLimit), { term, term, term }) or {})
end)

Kora.callback.register('kora_mdt:server:searchVehicles', function(src, query)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    local term = likeTerm(query)
    if not term then return nil, Kora.lang('Error.enter_at_least_two_characters') end
    return Kora.sql.query(([[SELECT v.`plate`,v.`model`,v.`citizenid`,v.`state`,p.`name` AS `owner_name`
        FROM `player_vehicles` v LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = v.`citizenid` COLLATE utf8mb4_unicode_ci AND p.`deleted_at` IS NULL
        WHERE v.`deleted_at` IS NULL AND (LOCATE(?,v.`plate`) > 0 OR LOCATE(?,v.`model`) > 0
            OR LOCATE(?,COALESCE(v.`citizenid`,'')) > 0 OR LOCATE(?,COALESCE(p.`name`,'')) > 0)
        ORDER BY v.`plate` LIMIT %d]]):format(C.operations.searchLimit), { term, term, term, term }) or {}
end)

Kora.callback.register('kora_mdt:server:reports', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    return listQuery('reports', ([[SELECT r.`id`,r.`title`,r.`status`,r.`subject_citizenid`,r.`charge_code`,c.`label` AS `charge_label`,
        r.`subject_text`,r.`charge_text`,r.`author_citizenid`,]] .. ts('r.`updated_at`') .. [[ AS `updated_at`,p.`name` AS `subject_name`
        FROM `kora_mdt_reports` r LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid` COLLATE utf8mb4_unicode_ci
        LEFT JOIN `kora_mdt_charges` c ON c.`code` COLLATE utf8mb4_unicode_ci = r.`charge_code` COLLATE utf8mb4_unicode_ci
        ORDER BY (r.`status` = 'open') DESC,r.`updated_at` DESC,r.`id` DESC LIMIT %d]]):format(C.operations.recentLimit))
end)

Kora.callback.register('kora_mdt:server:reportOptions', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    return listQuery('report options', [[SELECT r.`id`,r.`title`,
        COALESCE(p.`name`,r.`subject_citizenid`,r.`subject_text`,'Unknown') AS `subject`
        FROM `kora_mdt_reports` r
        LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid` COLLATE utf8mb4_unicode_ci
        ORDER BY r.`created_at` DESC,r.`id` DESC]])
end)

Kora.callback.register('kora_mdt:server:report', function(src, value)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    if not id then return nil, Kora.lang('Error.invalid_report') end
    return withTimes(Kora.sql.single([[SELECT r.`id`,r.`title`,r.`narrative`,r.`status`,r.`subject_citizenid`,r.`subject_text`,r.`charge_text`,r.`charge_code`,
        r.`author_citizenid`,DATE_FORMAT(r.`created_at`, '%Y-%m-%d %H:%i:%s') AS `created_at`,
        p.`name` AS `subject_name`,a.`name` AS `author_name`,c.`label` AS `charge_label`,c.`fine`
        FROM `kora_mdt_reports` r
        LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid` COLLATE utf8mb4_unicode_ci
        LEFT JOIN `players` a ON a.`citizenid` COLLATE utf8mb4_unicode_ci = r.`author_citizenid` COLLATE utf8mb4_unicode_ci
        LEFT JOIN `kora_mdt_charges` c ON c.`code` COLLATE utf8mb4_unicode_ci = r.`charge_code` COLLATE utf8mb4_unicode_ci WHERE r.`id` = ?]], { id }))
end)

local function createReport(src, input)
    local rules = C.reports or {}
    local title = cleanText(input.title, 160, false)
    local narrative = cleanText(input.narrative, 8000, false)
    local subjectText = cleanText(input.citizenid, 96, false)
    local chargeSelection = cleanText(input.charge, 128, false)
    local missing = missingRequired('report', { 'title', 'subject', 'charge', 'narrative' },
        { title = title, subject = subjectText, charge = chargeSelection, narrative = narrative })
    if missing then return nil, missing end

    local subject, subjectFree
    if subjectText ~= '' then
        local cid = cleanCid(subjectText)
        if cid and personExists(cid) then
            subject = cid
        else
            local resolved, ambiguous
            if rules.resolveSubjectByName ~= false then resolved, ambiguous = resolvePersonByName(subjectText) end
            if resolved then
                subject = resolved
            elseif ambiguous then
                return nil, Kora.lang('Error.more_than_one_citizen_is', subjectText)
            elseif cid and cid:find('%d') then
                return nil, Kora.lang('Error.citizen_id_not_found_check')
            elseif rules.allowUnknownSubject == false then
                return nil, Kora.lang('Error.subject_must_be_a_citizen', subjectText)
            else
                subjectFree = subjectText
            end
        end
    end

    local chargeCode, chargeFree
    if chargeSelection ~= '' then
        for _, cached in ipairs(chargeCache) do
            if cached.code:upper() == chargeSelection:upper() or cached.label:lower() == chargeSelection:lower() then
                chargeCode = cached.code
                break
            end
        end
        if not chargeCode then
            if rules.allowCustomCharges == false then
                return nil, Kora.lang('Error.is_not_in_the_charge', chargeSelection)
            end
            chargeFree = chargeSelection
        end
    end

    local author = citizenId(src)
    if not author then return nil, Kora.lang('Error.your_character_could_not_be') end
    -- A Lua table cannot hold nil, so absent optional values are bound as explicit SQL NULL.
    local NULL = Kora.sql.NULL
    local id, err = Kora.sql.insert([[INSERT INTO `kora_mdt_reports`
        (`title`,`narrative`,`subject_citizenid`,`subject_text`,`charge_code`,`charge_text`,`author_citizenid`) VALUES (?,?,?,?,?,?,?)]],
        { title, narrative, subject or NULL, subjectFree or NULL, chargeCode or NULL, chargeFree or NULL, author })
    if not id then
        logError('createReport insert failed', err)
        return nil, Kora.lang('Error.the_report_could_not_be')
    end
    if chargeCode and subject then
        local _, recordErr = Kora.sql.insert([[INSERT INTO `kora_mdt_criminal_records`
            (`citizenid`,`charge_code`,`notes`,`author_citizenid`) VALUES (?,?,?,?)]],
            { subject, chargeCode, Kora.lang('Error.report', id, title):sub(1, 1000), author })
        if recordErr then logError('createReport criminal record insert failed', recordErr) end
    end
    audit(src, 'report.create', 'report', id, title)
    return id
end

Kora.callback.register('kora_mdt:server:createReport', function(src, input)
    if not databaseReady then return nil, Kora.lang('Error.mdt_database_is_still_starting') end
    if not can(src, 'police') or type(input) ~= 'table' then return nil, Kora.lang('Error.not_authorised') end
    local ok, id, err = pcall(createReport, src, input)
    if not ok then
        logError('createReport raised an error', id)
        return nil, Kora.lang('Error.report_save_server_error')
    end
    return id, err
end)

Kora.callback.register('kora_mdt:server:closeReport', function(src, value)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    if not id then return false, Kora.lang('Error.invalid_report') end
    local changed, err = Kora.sql.update([[UPDATE `kora_mdt_reports` SET `status` = 'closed'
        WHERE `id` = ? AND `status` = 'open']], { id })
    if not changed or changed < 1 then return false, err or Kora.lang('Error.report_is_already_closed') end
    audit(src, 'report.close', 'report', id)
    return true
end)

Kora.callback.register('kora_mdt:server:cases', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    return listQuery('cases', ([[SELECT c.`id`,c.`title`,c.`priority`,c.`status`,c.`lead_citizenid`,]] .. ts('c.`updated_at`') .. [[ AS `updated_at`,
        (SELECT COUNT(*) FROM `kora_mdt_case_reports` cr WHERE cr.`case_id` = c.`id`) AS `report_count`
        FROM `kora_mdt_cases` c ORDER BY (c.`status` <> 'closed') DESC,c.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit))
end)

Kora.callback.register('kora_mdt:server:case', function(src, value)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    if not id then return nil, Kora.lang('Error.invalid_case') end
    local row = Kora.sql.single([[SELECT c.`id`,c.`title`,c.`summary`,c.`priority`,c.`status`,c.`lead_citizenid`,
        DATE_FORMAT(c.`created_at`, '%Y-%m-%d %H:%i:%s') AS `created_at`,
        DATE_FORMAT(c.`updated_at`, '%Y-%m-%d %H:%i:%s') AS `updated_at`,p.`name` AS `lead_name` FROM `kora_mdt_cases` c
        LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = c.`lead_citizenid` COLLATE utf8mb4_unicode_ci WHERE c.`id` = ?]], { id })
    if not row then return nil, Kora.lang('Error.case_not_found') end
    withTimes(row)
    row.reports = Kora.sql.query([[SELECT r.`id`,r.`title`,r.`status`,r.`subject_citizenid`,
        DATE_FORMAT(r.`updated_at`, '%Y-%m-%d %H:%i:%s') AS `updated_at`
        FROM `kora_mdt_case_reports` cr JOIN `kora_mdt_reports` r ON r.`id` = cr.`report_id`
        WHERE cr.`case_id` = ? ORDER BY r.`updated_at` DESC]], { id }) or {}
    withTimes(row.reports)
    return row
end)

Kora.callback.register('kora_mdt:server:createCase', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, Kora.lang('Error.not_authorised') end
    local title = cleanText(input.title, 160, false)
    local summary = cleanText(input.summary, 8000, false)
    local priorities = { low = true, normal = true, high = true, critical = true }
    local priority = priorities[input.priority] and input.priority or 'normal'
    local missing = missingRequired('case', { 'title', 'summary' }, { title = title, summary = summary })
    if missing then return nil, missing end

    local reportIds, seenReports = {}, {}
    local requestedReports = input.report_ids
    if requestedReports == nil and input.report_id ~= nil then requestedReports = { input.report_id } end
    if requestedReports ~= nil then
        if type(requestedReports) ~= 'table' then return nil, Kora.lang('Error.invalid_initial_reports') end
        for _, entry in ipairs(requestedReports) do
            local value = type(entry) == 'table' and entry.value or entry
            if type(value) == 'string' then
                local ok, decoded = pcall(function() return json.decode(value) end)
                if ok then value = decoded end
            end
            local reportId = cleanId(value)
            if not reportId then return nil, Kora.lang('Error.invalid_initial_report') end
            if not seenReports[reportId] then
                if not Kora.sql.single('SELECT `id` FROM `kora_mdt_reports` WHERE `id` = ?', { reportId }) then
                    return nil, Kora.lang('Error.initial_report_not_found')
                end
                seenReports[reportId] = true
                reportIds[#reportIds + 1] = reportId
            end
        end
    end

    local lead = citizenId(src)
    local id, err = Kora.sql.insert([[INSERT INTO `kora_mdt_cases`
        (`title`,`summary`,`priority`,`lead_citizenid`) VALUES (?,?,?,?)]], { title, summary, priority, lead })
    if not id then return nil, err or Kora.lang('Error.database_error') end
    for _, reportId in ipairs(reportIds) do
        Kora.sql.execute('INSERT IGNORE INTO `kora_mdt_case_reports` (`case_id`,`report_id`) VALUES (?,?)', { id, reportId })
    end
    audit(src, 'case.create', 'case', id, title)
    return id
end)

Kora.callback.register('kora_mdt:server:updateCaseStatus', function(src, value, status)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    local states = { open = true, investigating = true, closed = true }
    if not id or not states[status] then return false, Kora.lang('Error.invalid_case_status') end
    local changed, err = Kora.sql.update('UPDATE `kora_mdt_cases` SET `status` = ? WHERE `id` = ? AND `status` <> ?', { status, id, status })
    if not changed or changed < 1 then return false, err or Kora.lang('Error.case_already_has_that_status') end
    audit(src, 'case.status', 'case', id, status)
    return true
end)

Kora.callback.register('kora_mdt:server:linkCaseReport', function(src, caseValue, reportValue)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    local caseId, reportId = cleanId(caseValue), cleanId(reportValue)
    if not caseId or not reportId then return false, Kora.lang('Error.invalid_case_or_report') end
    if not Kora.sql.single('SELECT `id` FROM `kora_mdt_cases` WHERE `id` = ?', { caseId }) then return false, Kora.lang('Error.case_not_found') end
    if not Kora.sql.single('SELECT `id` FROM `kora_mdt_reports` WHERE `id` = ?', { reportId }) then return false, Kora.lang('Error.report_not_found') end
    local result, err = Kora.sql.execute('INSERT IGNORE INTO `kora_mdt_case_reports` (`case_id`,`report_id`) VALUES (?,?)', { caseId, reportId })
    if not result then return false, err or Kora.lang('Error.database_error') end
    local affectedRows = type(result) == 'table' and tonumber(result.affectedRows) or tonumber(result)
    if affectedRows == 0 then return false, Kora.lang('Error.report_is_already_linked') end
    audit(src, 'case.report.link', 'case', caseId, tostring(reportId))
    return true
end)

Kora.callback.register('kora_mdt:server:warrants', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    return listQuery('warrants', ([[SELECT w.`id`,w.`citizenid`,w.`reason`,
        IF(w.`status` = 'active' AND w.`expires_at` <= NOW(),'expired',w.`status`) AS `status`,
        DATE_FORMAT(w.`expires_at`, '%%Y-%%m-%%d %%H:%%i:%%s') AS `expires_at`,w.`author_citizenid`,p.`name` AS `subject_name`
        FROM `kora_mdt_warrants` w LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = w.`citizenid` COLLATE utf8mb4_unicode_ci
        ORDER BY (w.`status` = 'active' AND w.`expires_at` > NOW()) DESC,w.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit))
end)

Kora.callback.register('kora_mdt:server:createWarrant', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, Kora.lang('Error.not_authorised') end
    local target = cleanCid(input.citizenid)
    local reason = cleanText(input.reason, 1000, false)
    local days = math.max(1, math.min(C.operations.warrantMaxDays, math.floor(tonumber(input.days) or C.operations.warrantDefaultDays)))
    local missing = missingRequired('warrant', { 'citizenid', 'reason' }, { citizenid = target, reason = reason })
    if missing then return nil, missing end
    if not personExists(target) then return nil, Kora.lang('Error.citizen_id_not_found') end
    local id, err = Kora.sql.insert([[INSERT INTO `kora_mdt_warrants`
        (`citizenid`,`reason`,`author_citizenid`,`expires_at`) VALUES (?,?,?,DATE_ADD(NOW(), INTERVAL ? DAY))]],
        { target, reason, citizenId(src), days })
    if not id then return nil, err or Kora.lang('Error.database_error') end
    audit(src, 'warrant.create', 'warrant', id, target)
    return id
end)

Kora.callback.register('kora_mdt:server:closeWarrant', function(src, value, status)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    if not id or (status ~= 'served' and status ~= 'revoked') then return false, Kora.lang('Error.invalid_warrant_action') end
    local changed, err = Kora.sql.update([[UPDATE `kora_mdt_warrants` SET `status` = ?,`closed_by_citizenid` = ?
        WHERE `id` = ? AND `status` = 'active' AND `expires_at` > NOW()]], { status, citizenId(src), id })
    if not changed or changed < 1 then return false, err or Kora.lang('Error.warrant_is_not_active') end
    audit(src, 'warrant.' .. status, 'warrant', id)
    return true
end)

-- The BOLO Subject is the text the officer typed. Older rows have no
-- subject_text: earlier versions stored "Name (CID)" in subject_label and earlier rows only the
-- resolved citizen ID, so fall back without ever appending a citizen ID to a person.
local function boloSubject(row)
    if type(row.subject_text) == 'string' and row.subject_text ~= '' then return row.subject_text end
    local identifier = tostring(row.subject_identifier or '')
    if row.subject_type ~= 'person' then return identifier end
    local legacy = type(row.legacy_label) == 'string' and row.legacy_label or ''
    local suffix = ' (' .. identifier .. ')'
    if identifier ~= '' and #legacy > #suffix and legacy:sub(-#suffix) == suffix then legacy = legacy:sub(1, -#suffix - 1) end
    if legacy ~= '' and legacy ~= identifier then return legacy end
    if type(row.linked_name) == 'string' and row.linked_name ~= '' then return row.linked_name end
    return identifier
end

Kora.callback.register('kora_mdt:server:bolos', function(src)
    if not can(src, 'police') then return nil, Kora.lang('Error.not_authorised') end
    local rows, err = listQuery('BOLOs', ([[SELECT b.`id`,b.`subject_type`,b.`subject_identifier`,b.`subject_text`,
        b.`subject_label` AS `legacy_label`,p.`name` AS `linked_name`,p.`citizenid` AS `linked_citizenid`,
        b.`title`,b.`description`,
        IF(b.`status` = 'active' AND b.`expires_at` IS NOT NULL AND b.`expires_at` <= NOW(),'expired',b.`status`) AS `status`,
        b.`author_citizenid`,DATE_FORMAT(b.`expires_at`, '%%Y-%%m-%%d %%H:%%i:%%s') AS `expires_at`,]] .. ts('b.`updated_at`') .. [[ AS `updated_at` FROM `kora_mdt_bolos` b
        LEFT JOIN `players` p ON b.`subject_type` = 'person' AND p.`citizenid` COLLATE utf8mb4_unicode_ci = b.`subject_identifier` COLLATE utf8mb4_unicode_ci
        ORDER BY (b.`status` = 'active' AND (b.`expires_at` IS NULL OR b.`expires_at` > NOW())) DESC,b.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit))
    if not rows then return nil, err end
    for _, row in ipairs(rows) do
        row.subject_label = boloSubject(row)
        row.legacy_label, row.linked_name = nil, nil
    end
    return rows
end)

local function createBolo(src, input)
    local kinds = { person = true, vehicle = true }
    local kind = kinds[input.subject_type] and input.subject_type or nil
    local identifier = cleanText(input.identifier, 96, false)
    local title = cleanText(input.title, 160, false)
    local description = cleanText(input.description, 1500, false)
    local days = math.max(1, math.min(C.operations.boloMaxDays, math.floor(tonumber(input.days) or C.operations.boloDefaultDays)))
    if not kind then return nil, Kora.lang('Error.choose_a_valid_subject_type') end
    if identifier == '' then return nil, kind == 'vehicle' and 'Enter the vehicle plate.' or Kora.lang('Error.enter_a_citizen_id_or') end
    local missing = missingRequired('bolo', { 'title', 'description' }, { title = title, description = description })
    if missing then return nil, missing end
    -- subject_text is exactly what was typed and is the only thing shown as the subject.
    -- subject_identifier is the lookup key: a linked citizen ID (exact ID or exact unique
    -- name), the plate, or the free text itself.
    local typed = identifier
    if kind == 'person' then
        local rules = C.bolo or {}
        local cid = cleanCid(identifier)
        if cid and personExists(cid) then
            identifier = cid
        else
            local resolved, ambiguous
            if rules.resolvePersonByName ~= false then resolved, ambiguous = resolvePersonByName(identifier) end
            if resolved then
                identifier = resolved
            elseif ambiguous then
                return nil, Kora.lang('Error.more_than_one_citizen_is', identifier)
            elseif rules.allowUnknownPersonSubject == false then
                return nil, Kora.lang('Error.no_citizen_matches_enter_a', identifier)
            end
        end
    else
        identifier = identifier:upper()
    end
    local id, err = Kora.sql.insert([[INSERT INTO `kora_mdt_bolos`
        (`subject_type`,`subject_identifier`,`subject_text`,`title`,`description`,`author_citizenid`,`expires_at`)
        VALUES (?,?,?,?,?,?,DATE_ADD(NOW(), INTERVAL ? DAY))]], { kind, identifier, typed, title, description, citizenId(src), days })
    if not id then
        logError('createBolo insert failed', err)
        return nil, Kora.lang('Error.the_bolo_could_not_be')
    end
    audit(src, 'bolo.create', 'bolo', id, identifier)
    return id
end

Kora.callback.register('kora_mdt:server:createBolo', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, Kora.lang('Error.not_authorised') end
    local ok, id, err = pcall(createBolo, src, input)
    if not ok then
        logError('createBolo raised an error', id)
        return nil, Kora.lang('Error.bolo_save_server_error')
    end
    return id, err
end)

Kora.callback.register('kora_mdt:server:resolveBolo', function(src, value)
    if not can(src, 'police') then return false, Kora.lang('Error.not_authorised') end
    local id = cleanId(value)
    if not id then return false, Kora.lang('Error.invalid_bolo') end
    local changed, err = Kora.sql.update("UPDATE `kora_mdt_bolos` SET `status` = 'resolved' WHERE `id` = ? AND `status` = 'active'", { id })
    if not changed or changed < 1 then return false, err or Kora.lang('Error.bolo_is_not_active') end
    audit(src, 'bolo.resolve', 'bolo', id)
    return true
end)

-- Three-stage analysis is driven by kora_lib proofs. The client cannot claim a
-- pass: each stage consumes the one-use server proof generated by kora_lib.
local analysis = {}
local function hasEvidenceCase(src, caseId)
    local bags = exports.kora_inventory:GetItemsByName(src, 'filled_evidence_bag') or {}
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
    return Kora.minigames.authorizeProof(src, definition.game, opts)
end

Kora.events.register('kora_mdt:server:open', function(src)
    local userRole = role(src)
    if not userRole then
        return Kora.notify.send(src, {
            title = Kora.lang('Terminal.mdt'),
            message = Kora.lang('Notify.you_must_be_on_duty'),
            type = 'error',
        })
    end
    TriggerClientEvent('kora_mdt:client:open', src, userRole, isPoliceBoss(src))
end, { rateLimit = { max = 4, window = 2000 } })
Kora.events.register('kora_mdt:server:beginAnalysis', function(src, caseId)
    if not can(src, 'police') or type(caseId) ~= 'string' then return end
    local existing = analysis[src]
    if existing and existing.expiresAt < GetGameTimer() then analysis[src] = nil; existing = nil end
    if existing or not hasEvidenceCase(src, caseId) then return end

    local authorization = authorizeAnalysisStage(src, 1)
    if not authorization then return end
    local state = {
        caseId = caseId,
        stage = 1,
        authorization = authorization,
        expiresAt = GetGameTimer() + C.analysis.ttl,
    }
    analysis[src] = state
    SetTimeout(C.analysis.ttl + 1, function()
        if analysis[src] == state then analysis[src] = nil end
    end)
    TriggerClientEvent('kora_mdt:client:analysisStage', src, 1, authorization)
end, { rateLimit = { max = 2, window = 3000 } })
Kora.events.register('kora_mdt:server:cancelAnalysis', function(src)
    analysis[src] = nil
end, { rateLimit = { max = 4, window = 3000 } })
Kora.events.register('kora_mdt:server:analysisStage', function(src, token)
    local state = analysis[src]
    if not state or type(token) ~= 'string' then return end
    if state.expiresAt < GetGameTimer() or not can(src, 'police')
        or not hasEvidenceCase(src, state.caseId) then analysis[src] = nil; return end

    local definition = C.analysis.stages[state.stage]
    if not definition or not Kora.minigames.consumeProof(src, token,
        definition.game, state.authorization) then return end

    state.stage = state.stage + 1
    if state.stage <= #C.analysis.stages then
        state.authorization = authorizeAnalysisStage(src, state.stage)
        if not state.authorization then analysis[src] = nil; return end
        return TriggerClientEvent('kora_mdt:client:analysisStage', src, state.stage, state.authorization)
    end
    local row = exports.kora_police:GetBallisticCasing(state.caseId)
    analysis[src] = nil
    if row then TriggerClientEvent('kora_mdt:client:analysisComplete', src, { caseId = state.caseId, weaponSerial = row.weapon_serial, weapon = row.weapon_name }) end
end, { rateLimit = { max = 5, window = 5000 } })

local function issueWeaponLicence(src, state)
    local cid = citizenId(src)
    if cid ~= state.citizenid or hasWeaponLicense(src) then return false end

    local number = ('WPN-%s-%04d'):format(cid:sub(-6):upper(), math.random(0, 9999))
    local written = Kora.sql.execute([[INSERT INTO `kora_mdt_licences`
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
    return exports.kora_core:setMetaData(src, 'licences', licences) == true
end

local function finishTraining(src, state, passed, silent)
    if training[src] ~= state or state.finishing then return end
    state.finishing = true
    exports.kora_inventory:StopTrainingWeapon(src)

    passed = passed == true and issueWeaponLicence(src, state)
    if training[src] == state then training[src] = nil end
    if not silent then TriggerClientEvent('kora_mdt:client:weaponLicenceResult', src, passed, state.shots) end
end

local function stillEligible(src, state)
    return state.expiresAt >= GetGameTimer()
        and state.citizenid == citizenId(src)
        and state.bucket == GetPlayerRoutingBucket(src)
        and nearWeaponLicenceZone(src)
end

local function beginQualification(src, state)
    if training[src] ~= state or state.authorization then return end
    local definition = C.weaponLicence.qualification
    local authorization = Kora.minigames.authorizeProof(src, definition.game, definition.opts)
    if not authorization then return finishTraining(src, state, false) end
    state.authorization = authorization
    TriggerClientEvent('kora_mdt:client:weaponLicenceQualification', src, authorization)
end

Kora.events.register('kora_mdt:server:startWeaponLicence', function(src)
    if training[src] then
        return Kora.notify.send(src, { title = Kora.lang('Terminal.weapon_licence'), message = Kora.lang('Notify.a_range_session_is_already'), type = 'error' })
    end
    if not nearWeaponLicenceZone(src, C.weaponLicence.interactionDistance) then
        return Kora.notify.send(src, { title = Kora.lang('Terminal.weapon_licence'), message = Kora.lang('Notify.move_closer_to_the_range'), type = 'error' })
    end

    local cid = citizenId(src)
    local bucket = GetPlayerRoutingBucket(src)
    if not cid then return end
    if hasWeaponLicense(src) then
        return Kora.notify.send(src, { title = Kora.lang('Terminal.weapon_licence'), message = Kora.lang('Notify.you_already_hold_a_weapon'), type = 'error' })
    end

    local state = {
        citizenid = cid,
        shots = 0,
        bucket = bucket,
        expiresAt = GetGameTimer() + C.weaponLicence.trainingTimeout,
    }
    local started, startErr = exports.kora_inventory:StartTrainingWeapon(src, C.weaponLicence.weapon, C.weaponLicence.shots)
    if not started then
        return Kora.notify.send(src, { title = Kora.lang('Terminal.weapon_licence'), message = startErr or Kora.lang('Error.the_range_is_unavailable'), type = 'error' })
    end

    training[src] = state
    TriggerClientEvent('kora_mdt:client:weaponLicenceStart', src, {
        targetModel = C.weaponLicence.targetModel,
        targetHeading = C.weaponLicence.targetHeading,
        range = C.weaponLicence.range,
        targetOffsets = C.weaponLicence.targetOffsets,
        shots = C.weaponLicence.shots,
        weapon = C.weaponLicence.weapon,
    })
    SetTimeout(C.weaponLicence.trainingTimeout, function()
        if training[src] == state then finishTraining(src, state, false) end
    end)
end, { rateLimit = { max = 1, window = 2000 } })

AddEventHandler('kora_inventory:server:trainingRoundFired', function(src, round)
    local state = training[src]
    if not state or type(round) ~= 'table' or round.owner ~= GetCurrentResourceName()
        or round.weapon ~= C.weaponLicence.weapon or round.shot ~= state.shots + 1 then return end
    if not stillEligible(src, state) then return finishTraining(src, state, false) end

    state.shots = round.shot
    -- The range test is the live-fire exercise.  Once every issued training
    -- round has been fired, finish it immediately instead of making a target
    -- hit look like a failure because of a separate handling minigame.
    if state.shots >= C.weaponLicence.shots then finishTraining(src, state, true) end
end)

Kora.events.register('kora_mdt:server:completeWeaponLicence', function(src, proof)
    local state = training[src]
    local definition = C.weaponLicence.qualification
    if not state or state.shots < C.weaponLicence.shots or type(proof) ~= 'string'
        or not stillEligible(src, state) or not state.authorization then return end
    if not Kora.minigames.consumeProof(src, proof, definition.game, state.authorization) then return end
    finishTraining(src, state, true)
end, { rateLimit = { max = 3, window = 5000 } })

Kora.events.register('kora_mdt:server:cancelWeaponLicence', function(src)
    local state = training[src]
    if state then finishTraining(src, state, false) end
end, { rateLimit = { max = 3, window = 5000 } })

AddEventHandler('playerDropped', function()
    local src, state = source, training[source]
    if state then finishTraining(src, state, false, true) end
    analysis[src] = nil
end)
