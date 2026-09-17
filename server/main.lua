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
local function cleanText(value, maximum, required)
    if type(value) ~= 'string' then return required and nil or '' end
    value = value:gsub('[%z\1-\8\11\12\14-\31]', ''):match('^%s*(.-)%s*$')
    if value == '' and required then return nil end
    return value:sub(1, maximum)
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
    return cid and QB.sql.single('SELECT `citizenid` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { cid }) ~= nil
end
local function audit(src, action, targetType, targetId, details)
    local actor = citizenId(src)
    if not actor then return end
    QB.sql.insert([[INSERT INTO `qbmdt_audit_log`
        (`actor_citizenid`,`action`,`target_type`,`target_id`,`details`) VALUES (?,?,?,?,?)]],
        { actor, action, targetType, tostring(targetId), cleanText(details, 1000, false) })
end
local function near(src, coords, distance)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z)) <= distance
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
    if payload.count ~= 1 then return false end
    if not hasWeaponLicense(src) then return 'You need a weapon licence to purchase firearms.' end
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
    local identity = QB.sql.single('SELECT `citizenid`,`name`,`phone_number`,`charinfo`,`job`,`metadata` FROM `players` WHERE `citizenid` = ? AND `deleted_at` IS NULL', { wanted })
    if not identity then return nil, 'person not found' end
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
        out.firearms = QB.sql.query('SELECT `serial`,`weapon_name`,`purchased_at` FROM `qbmdt_firearms` WHERE `owner_citizenid` = ? ORDER BY `purchased_at` DESC', { wanted }) or {}
        out.criminal = QB.sql.query('SELECT `charge_code`,`notes`,`created_at` FROM `qbmdt_criminal_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
        out.reports = QB.sql.query([[SELECT `id`,`title`,`status`,`created_at` FROM `qbmdt_reports`
            WHERE `subject_citizenid` = ? ORDER BY `created_at` DESC LIMIT 25]], { wanted }) or {}
        out.warrants = QB.sql.query([[SELECT `id`,`reason`,`expires_at` FROM `qbmdt_warrants`
            WHERE `citizenid` = ? AND `status` = 'active' AND `expires_at` > NOW() ORDER BY `expires_at`]], { wanted }) or {}
        out.bolos = QB.sql.query([[SELECT `id`,`title`,`description`,`expires_at` FROM `qbmdt_bolos`
            WHERE `subject_type` = 'person' AND `subject_identifier` = ? AND `status` = 'active'
            AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC]], { wanted }) or {}
    end
    if r == 'medical' or r == 'judge' then
        out.medical = QB.sql.query('SELECT `notes`,`created_at` FROM `qbmdt_medical_records` WHERE `citizenid` = ? ORDER BY `created_at` DESC', { wanted }) or {}
    end
    return out
end)

QB.callback.register('qbmdt:server:vehicle', function(src, plate)
    if not can(src, 'police') then return nil, 'not authorised' end
    plate = type(plate) == 'string' and plate:gsub('^%s+', ''):gsub('%s+$', ''):upper() or ''
    if plate == '' or #plate > 15 then return nil, 'invalid plate' end
    local vehicle = QB.sql.single([[SELECT v.`plate`,v.`model`,v.`citizenid`,v.`state`,v.`garage_id`,v.`impound_lot`,p.`name` AS `owner_name`
        FROM `player_vehicles` v LEFT JOIN `players` p ON p.`citizenid` = v.`citizenid`
        WHERE v.`plate` = ? AND v.`deleted_at` IS NULL]], { plate })
    if vehicle then
        vehicle.bolos = QB.sql.query([[SELECT `id`,`title`,`description`,`expires_at` FROM `qbmdt_bolos`
            WHERE `subject_type` = 'vehicle' AND `subject_identifier` = ? AND `status` = 'active'
            AND (`expires_at` IS NULL OR `expires_at` > NOW()) ORDER BY `created_at` DESC]], { plate }) or {}
    end
    return vehicle
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
    if not personExists(wanted) then return false, 'citizen not found' end
    local written, err = QB.sql.execute('INSERT INTO `qbmdt_criminal_records` (`citizenid`,`charge_code`,`notes`,`author_citizenid`) VALUES (?,?,?,?)',
        { wanted, code, tostring(notes or ''):sub(1, 1000), author })
    if not written then return false, err or 'database error' end
    audit(src, 'criminal.create', 'citizen', wanted, code)
    return true
end)

QB.callback.register('qbmdt:server:addMedical', function(src, wanted, notes)
    if not can(src, 'medical') then return false, 'not authorised' end
    wanted = cleanCid(wanted)
    local author = citizenId(src)
    if not wanted or not author or type(notes) ~= 'string' or notes == '' then return false, 'invalid record' end
    if not personExists(wanted) then return false, 'citizen not found' end
    local written, err = QB.sql.execute('INSERT INTO `qbmdt_medical_records` (`citizenid`,`notes`,`author_citizenid`) VALUES (?,?,?)',
        { wanted, notes:sub(1, 1000), author })
    if not written then return false, err or 'database error' end
    audit(src, 'medical.create', 'citizen', wanted)
    return true
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

-- Operational MDT data. These callbacks deliberately keep search limits and
-- all mutations on the server; the AppShell is a presentation layer, not an
-- authority boundary.
QB.callback.register('qbmdt:server:dashboard', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    local counts = QB.sql.single([[SELECT
        (SELECT COUNT(*) FROM `qbmdt_reports` WHERE `status` = 'open') AS `open_reports`,
        (SELECT COUNT(*) FROM `qbmdt_cases` WHERE `status` <> 'closed') AS `open_cases`,
        (SELECT COUNT(*) FROM `qbmdt_warrants` WHERE `status` = 'active' AND `expires_at` > NOW()) AS `active_warrants`,
        (SELECT COUNT(*) FROM `qbmdt_bolos` WHERE `status` = 'active' AND (`expires_at` IS NULL OR `expires_at` > NOW())) AS `active_bolos`]]) or {}
    counts.recent = QB.sql.query([[SELECT `id`,`title`,`status`,`author_citizenid`,`updated_at`
        FROM `qbmdt_reports` ORDER BY `updated_at` DESC LIMIT 8]]) or {}
    return counts
end)

QB.callback.register('qbmdt:server:searchPeople', function(src, query)
    if not role(src) then return nil, 'not authorised' end
    local term = likeTerm(query)
    if not term then return nil, 'enter at least two characters' end
    return QB.sql.query(([[SELECT `citizenid`,`name`,`phone_number`,`last_updated`
        FROM `players` WHERE `deleted_at` IS NULL
        AND (LOCATE(?,`citizenid`) > 0 OR LOCATE(?,`name`) > 0 OR LOCATE(?,COALESCE(`phone_number`,'')) > 0)
        ORDER BY `name` LIMIT %d]]):format(C.operations.searchLimit), { term, term, term }) or {}
end)

QB.callback.register('qbmdt:server:searchVehicles', function(src, query)
    if not can(src, 'police') then return nil, 'not authorised' end
    local term = likeTerm(query)
    if not term then return nil, 'enter at least two characters' end
    return QB.sql.query(([[SELECT v.`plate`,v.`model`,v.`citizenid`,v.`state`,p.`name` AS `owner_name`
        FROM `player_vehicles` v LEFT JOIN `players` p ON p.`citizenid` = v.`citizenid` AND p.`deleted_at` IS NULL
        WHERE v.`deleted_at` IS NULL AND (LOCATE(?,v.`plate`) > 0 OR LOCATE(?,v.`model`) > 0
            OR LOCATE(?,COALESCE(v.`citizenid`,'')) > 0 OR LOCATE(?,COALESCE(p.`name`,'')) > 0)
        ORDER BY v.`plate` LIMIT %d]]):format(C.operations.searchLimit), { term, term, term, term }) or {}
end)

QB.callback.register('qbmdt:server:reports', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.query(([[SELECT r.`id`,r.`title`,r.`status`,r.`subject_citizenid`,r.`charge_code`,
        r.`author_citizenid`,r.`updated_at`,p.`name` AS `subject_name`
        FROM `qbmdt_reports` r LEFT JOIN `players` p ON p.`citizenid` = r.`subject_citizenid`
        ORDER BY (r.`status` = 'open') DESC,r.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit)) or {}
end)

QB.callback.register('qbmdt:server:report', function(src, value)
    if not can(src, 'police') then return nil, 'not authorised' end
    local id = cleanId(value)
    if not id then return nil, 'invalid report' end
    return QB.sql.single([[SELECT r.*,p.`name` AS `subject_name`,a.`name` AS `author_name`,c.`label` AS `charge_label`,c.`fine`
        FROM `qbmdt_reports` r
        LEFT JOIN `players` p ON p.`citizenid` = r.`subject_citizenid`
        LEFT JOIN `players` a ON a.`citizenid` = r.`author_citizenid`
        LEFT JOIN `qbmdt_charges` c ON c.`code` = r.`charge_code` WHERE r.`id` = ?]], { id })
end)

QB.callback.register('qbmdt:server:createReport', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, 'not authorised' end
    local title = cleanText(input.title, 160, true)
    local narrative = cleanText(input.narrative, 8000, true)
    local subject = cleanCid(input.citizenid)
    local chargeCode = cleanText(input.charge, 32, false):upper()
    if not title or not narrative then return nil, 'title and narrative are required' end
    if input.citizenid and input.citizenid ~= '' and not personExists(subject) then return nil, 'citizen not found' end
    if chargeCode ~= '' then
        local charge = QB.sql.single('SELECT `code` FROM `qbmdt_charges` WHERE `code` = ? AND `active` = 1', { chargeCode })
        if not charge then return nil, 'unknown charge' end
        if not subject then return nil, 'a charged report requires a citizen ID' end
    else
        chargeCode = nil
    end
    local author = citizenId(src)
    if not author then return nil, 'author unavailable' end
    local id, err = QB.sql.insert([[INSERT INTO `qbmdt_reports`
        (`title`,`narrative`,`subject_citizenid`,`charge_code`,`author_citizenid`) VALUES (?,?,?,?,?)]],
        { title, narrative, subject, chargeCode, author })
    if not id then return nil, err or 'database error' end
    if chargeCode then
        QB.sql.insert([[INSERT INTO `qbmdt_criminal_records`
            (`citizenid`,`charge_code`,`notes`,`author_citizenid`) VALUES (?,?,?,?)]],
            { subject, chargeCode, ('Report #%s: %s'):format(id, title):sub(1, 1000), author })
    end
    audit(src, 'report.create', 'report', id, title)
    return id
end)

QB.callback.register('qbmdt:server:closeReport', function(src, value)
    if not can(src, 'police') then return false, 'not authorised' end
    local id = cleanId(value)
    if not id then return false, 'invalid report' end
    local changed, err = QB.sql.update([[UPDATE `qbmdt_reports` SET `status` = 'closed'
        WHERE `id` = ? AND `status` = 'open']], { id })
    if not changed or changed < 1 then return false, err or 'report is already closed' end
    audit(src, 'report.close', 'report', id)
    return true
end)

QB.callback.register('qbmdt:server:cases', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.query(([[SELECT c.`id`,c.`title`,c.`priority`,c.`status`,c.`lead_citizenid`,c.`updated_at`,
        (SELECT COUNT(*) FROM `qbmdt_case_reports` cr WHERE cr.`case_id` = c.`id`) AS `report_count`
        FROM `qbmdt_cases` c ORDER BY (c.`status` <> 'closed') DESC,c.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit)) or {}
end)

QB.callback.register('qbmdt:server:case', function(src, value)
    if not can(src, 'police') then return nil, 'not authorised' end
    local id = cleanId(value)
    if not id then return nil, 'invalid case' end
    local row = QB.sql.single([[SELECT c.*,p.`name` AS `lead_name` FROM `qbmdt_cases` c
        LEFT JOIN `players` p ON p.`citizenid` = c.`lead_citizenid` WHERE c.`id` = ?]], { id })
    if not row then return nil, 'case not found' end
    row.reports = QB.sql.query([[SELECT r.`id`,r.`title`,r.`status`,r.`subject_citizenid`,r.`updated_at`
        FROM `qbmdt_case_reports` cr JOIN `qbmdt_reports` r ON r.`id` = cr.`report_id`
        WHERE cr.`case_id` = ? ORDER BY r.`updated_at` DESC]], { id }) or {}
    return row
end)

QB.callback.register('qbmdt:server:createCase', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, 'not authorised' end
    local title = cleanText(input.title, 160, true)
    local summary = cleanText(input.summary, 8000, true)
    local priorities = { low = true, normal = true, high = true, critical = true }
    local priority = priorities[input.priority] and input.priority or 'normal'
    if not title or not summary then return nil, 'title and summary are required' end
    local lead = citizenId(src)
    local id, err = QB.sql.insert([[INSERT INTO `qbmdt_cases`
        (`title`,`summary`,`priority`,`lead_citizenid`) VALUES (?,?,?,?)]], { title, summary, priority, lead })
    if not id then return nil, err or 'database error' end
    local reportId = cleanId(input.report_id)
    if reportId and QB.sql.single('SELECT `id` FROM `qbmdt_reports` WHERE `id` = ?', { reportId }) then
        QB.sql.execute('INSERT IGNORE INTO `qbmdt_case_reports` (`case_id`,`report_id`) VALUES (?,?)', { id, reportId })
    end
    audit(src, 'case.create', 'case', id, title)
    return id
end)

QB.callback.register('qbmdt:server:updateCaseStatus', function(src, value, status)
    if not can(src, 'police') then return false, 'not authorised' end
    local id = cleanId(value)
    local states = { open = true, investigating = true, closed = true }
    if not id or not states[status] then return false, 'invalid case status' end
    local changed, err = QB.sql.update('UPDATE `qbmdt_cases` SET `status` = ? WHERE `id` = ? AND `status` <> ?', { status, id, status })
    if not changed or changed < 1 then return false, err or 'case already has that status' end
    audit(src, 'case.status', 'case', id, status)
    return true
end)

QB.callback.register('qbmdt:server:linkCaseReport', function(src, caseValue, reportValue)
    if not can(src, 'police') then return false, 'not authorised' end
    local caseId, reportId = cleanId(caseValue), cleanId(reportValue)
    if not caseId or not reportId then return false, 'invalid case or report' end
    if not QB.sql.single('SELECT `id` FROM `qbmdt_cases` WHERE `id` = ?', { caseId }) then return false, 'case not found' end
    if not QB.sql.single('SELECT `id` FROM `qbmdt_reports` WHERE `id` = ?', { reportId }) then return false, 'report not found' end
    local written, err = QB.sql.execute('INSERT IGNORE INTO `qbmdt_case_reports` (`case_id`,`report_id`) VALUES (?,?)', { caseId, reportId })
    if not written or written < 1 then return false, err or 'report is already linked' end
    audit(src, 'case.report.link', 'case', caseId, tostring(reportId))
    return true
end)

QB.callback.register('qbmdt:server:warrants', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.query(([[SELECT w.`id`,w.`citizenid`,w.`reason`,
        IF(w.`status` = 'active' AND w.`expires_at` <= NOW(),'expired',w.`status`) AS `status`,
        w.`expires_at`,w.`author_citizenid`,p.`name` AS `subject_name`
        FROM `qbmdt_warrants` w LEFT JOIN `players` p ON p.`citizenid` = w.`citizenid`
        ORDER BY (w.`status` = 'active' AND w.`expires_at` > NOW()) DESC,w.`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit)) or {}
end)

QB.callback.register('qbmdt:server:createWarrant', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, 'not authorised' end
    local target = cleanCid(input.citizenid)
    local reason = cleanText(input.reason, 1000, true)
    local days = math.max(1, math.min(C.operations.warrantMaxDays, math.floor(tonumber(input.days) or C.operations.warrantDefaultDays)))
    if not personExists(target) then return nil, 'citizen not found' end
    if not reason then return nil, 'reason is required' end
    local id, err = QB.sql.insert([[INSERT INTO `qbmdt_warrants`
        (`citizenid`,`reason`,`author_citizenid`,`expires_at`) VALUES (?,?,?,DATE_ADD(NOW(), INTERVAL ? DAY))]],
        { target, reason, citizenId(src), days })
    if not id then return nil, err or 'database error' end
    audit(src, 'warrant.create', 'warrant', id, target)
    return id
end)

QB.callback.register('qbmdt:server:closeWarrant', function(src, value, status)
    if not can(src, 'police') then return false, 'not authorised' end
    local id = cleanId(value)
    if not id or (status ~= 'served' and status ~= 'revoked') then return false, 'invalid warrant action' end
    local changed, err = QB.sql.update([[UPDATE `qbmdt_warrants` SET `status` = ?,`closed_by_citizenid` = ?
        WHERE `id` = ? AND `status` = 'active' AND `expires_at` > NOW()]], { status, citizenId(src), id })
    if not changed or changed < 1 then return false, err or 'warrant is not active' end
    audit(src, 'warrant.' .. status, 'warrant', id)
    return true
end)

QB.callback.register('qbmdt:server:bolos', function(src)
    if not can(src, 'police') then return nil, 'not authorised' end
    return QB.sql.query(([[SELECT `id`,`subject_type`,`subject_identifier`,`title`,`description`,
        IF(`status` = 'active' AND `expires_at` IS NOT NULL AND `expires_at` <= NOW(),'expired',`status`) AS `status`,
        `author_citizenid`,`expires_at`,`updated_at` FROM `qbmdt_bolos`
        ORDER BY (`status` = 'active' AND (`expires_at` IS NULL OR `expires_at` > NOW())) DESC,`updated_at` DESC LIMIT %d]]):format(C.operations.recentLimit)) or {}
end)

QB.callback.register('qbmdt:server:createBolo', function(src, input)
    if not can(src, 'police') or type(input) ~= 'table' then return nil, 'not authorised' end
    local kinds = { person = true, vehicle = true }
    local kind = kinds[input.subject_type] and input.subject_type or nil
    local identifier = cleanText(input.identifier, 96, true)
    local title = cleanText(input.title, 160, true)
    local description = cleanText(input.description, 1500, true)
    local days = math.max(1, math.min(C.operations.boloMaxDays, math.floor(tonumber(input.days) or C.operations.boloDefaultDays)))
    if not kind or not identifier or not title or not description then return nil, 'all BOLO fields are required' end
    if kind == 'person' and not personExists(cleanCid(identifier)) then return nil, 'citizen not found' end
    if kind == 'vehicle' then identifier = identifier:upper() end
    local id, err = QB.sql.insert([[INSERT INTO `qbmdt_bolos`
        (`subject_type`,`subject_identifier`,`title`,`description`,`author_citizenid`,`expires_at`)
        VALUES (?,?,?,?,?,DATE_ADD(NOW(), INTERVAL ? DAY))]], { kind, identifier, title, description, citizenId(src), days })
    if not id then return nil, err or 'database error' end
    audit(src, 'bolo.create', 'bolo', id, identifier)
    return id
end)

QB.callback.register('qbmdt:server:resolveBolo', function(src, value)
    if not can(src, 'police') then return false, 'not authorised' end
    local id = cleanId(value)
    if not id then return false, 'invalid BOLO' end
    local changed, err = QB.sql.update("UPDATE `qbmdt_bolos` SET `status` = 'resolved' WHERE `id` = ? AND `status` = 'active'", { id })
    if not changed or changed < 1 then return false, err or 'BOLO is not active' end
    audit(src, 'bolo.resolve', 'bolo', id)
    return true
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
    if not userRole then
        return QB.notify.send(src, {
            title = 'MDT',
            message = 'You must be on duty as police, EMS, or a judge to use the MDT.',
            type = 'error',
        })
    end
    TriggerClientEvent('qbmdt:client:open', src, userRole)
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
        and nearWeaponLicenceZone(src)
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
    if training[src] then
        return QB.notify.send(src, { title = 'Weapon licence', message = 'A range session is already in progress.', type = 'error' })
    end
    if not nearWeaponLicenceZone(src, C.weaponLicence.interactionDistance) then
        return QB.notify.send(src, { title = 'Weapon licence', message = 'Move closer to the range marker.', type = 'error' })
    end

    local cid = citizenId(src)
    local bucket = GetPlayerRoutingBucket(src)
    if not cid then return end
    if hasWeaponLicense(src) then
        return QB.notify.send(src, { title = 'Weapon licence', message = 'You already hold a weapon licence.', type = 'error' })
    end

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
        weapon = C.weaponLicence.weapon,
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
    -- The range test is the live-fire exercise.  Once every issued training
    -- round has been fired, finish it immediately instead of making a target
    -- hit look like a failure because of a separate handling minigame.
    if state.shots >= C.weaponLicence.shots then finishTraining(src, state, true) end
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
