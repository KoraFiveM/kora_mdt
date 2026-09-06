local C = Config.mdt
local training, trainingTargets = false, {}

local function form(title, fields)
    local result = QB.nui.openInputDialog(fields, title)
    if not result or result.cancelled then return nil end
    return result.values
end
local function notify(message, kind)
    QB.notify.send({ title = 'MDT', message = message, type = kind or 'info' })
end
local function lines(records, formatter)
    local out = {}
    for _, row in ipairs(records or {}) do out[#out + 1] = formatter(row) end
    return #out > 0 and table.concat(out, '\n') or 'None on file.'
end

local function openTerminal(role)
    if role ~= 'police' and role ~= 'medical' and role ~= 'judge' then return end

    local hasCriminalRecords = role == 'police' or role == 'judge'
    local hasMedicalRecords = role == 'medical' or role == 'judge'
    local hasPoliceTools = role == 'police' or role == 'judge'
    local lookupActions = {
        { id = 'person', label = hasMedicalRecords and not hasCriminalRecords and 'Patient lookup' or 'Person & licence lookup', icon = 'contact' },
    }
    local navigation = {}

    if hasPoliceTools then
        lookupActions[#lookupActions + 1] = { id = 'vehicle', label = 'Vehicle lookup', icon = 'car-front' }
        lookupActions[#lookupActions + 1] = { id = 'charges', label = 'Available charges', icon = 'scale' }
        lookupActions[#lookupActions + 1] = { id = 'firearm', label = 'Firearm registration lookup', icon = 'crosshair' }
    end

    navigation[#navigation + 1] = {
        id = 'lookup', label = hasMedicalRecords and not hasCriminalRecords and 'Patients' or 'Lookups', icon = 'search',
        content = { title = hasMedicalRecords and not hasCriminalRecords and 'Patient lookup' or 'Records lookup', blocks = { { type = 'actions', actions = lookupActions } } },
    }
    if hasCriminalRecords then
        navigation[#navigation + 1] = {
            id = 'criminal-records', label = 'Criminal records', icon = 'files',
            content = { title = 'Criminal records', blocks = { { type = 'actions', actions = {
                { id = 'criminal', label = 'Add criminal record', icon = 'file-plus' },
                { id = 'analysis', label = 'Analyse ballistic casing', icon = 'microscope' },
            } } } },
        }
    end
    if hasMedicalRecords then
        navigation[#navigation + 1] = {
            id = 'medical-records', label = 'Medical records', icon = 'heart-pulse',
            content = { title = 'Medical records', blocks = { { type = 'actions', actions = {
                { id = 'medical', label = 'Add medical record', icon = 'file-plus' },
            } } } },
        }
    end

    QB.nui.registerApp({
        id = 'qbmdt:terminal',
        title = role == 'medical' and 'Medical Records Terminal' or 'Mobile Data Terminal',
        description = role == 'medical' and 'Patient and medical records' or 'Criminal records and case tools',
        icon = role == 'medical' and 'heart-pulse' or 'monitor-smartphone',
        navigation = navigation,
        footer = 'Records access is verified by the server.',
        onAction = function(selectedId)
            if selectedId == 'criminal' or selectedId == 'analysis' then
                if not hasCriminalRecords then return {} end
            elseif selectedId == 'medical' then
                if not hasMedicalRecords then return {} end
            elseif selectedId == 'vehicle' or selectedId == 'charges' or selectedId == 'firearm' then
                if not hasPoliceTools then return {} end
            end
            if selectedId == 'person' then
        local input = form('Person lookup', { { id = 'citizenid', label = 'Citizen ID', required = true } })
        if not input then return {} end
        local record, err = QB.callback.trigger('qbmdt:server:person', input.citizenid)
        if not record then notify(err or 'No record found.', 'error'); return {} end
        local detail = ('%s\nDriver licence: %s'):format(record.name, record.driverLicensed and 'valid' or 'not held')
        if record.weaponLicence then detail = detail .. '\nWeapon licence: ' .. record.weaponLicence end
        if record.firearms then detail = detail .. '\nFirearms:\n' .. lines(record.firearms, function(r) return r.weapon_name .. ' — ' .. r.serial end) end
        if record.criminal then detail = detail .. '\nCriminal:\n' .. lines(record.criminal, function(r) return r.charge_code .. ': ' .. (r.notes or '') end) end
        if record.medical then detail = detail .. '\nMedical:\n' .. lines(record.medical, function(r) return r.notes end) end
        notify(detail)
    elseif selectedId == 'vehicle' then
        local input = form('Vehicle lookup', { { id = 'plate', label = 'Plate', required = true } })
        if not input then return {} end
        local row, err = QB.callback.trigger('qbmdt:server:vehicle', input.plate)
        notify(row and ('%s — owner %s — %s'):format(row.plate, row.citizenid, row.state) or (err or 'No vehicle found.'), row and 'info' or 'error')
    elseif selectedId == 'charges' then
        local rows, err = QB.callback.trigger('qbmdt:server:charges')
        notify(rows and lines(rows, function(r) return ('%s: %s ($%d)'):format(r.code, r.label, r.fine) end) or (err or 'Not authorised.'), rows and 'info' or 'error')
    elseif selectedId == 'criminal' then
        local input = form('Criminal record', {
            { id = 'citizenid', label = 'Citizen ID', required = true }, { id = 'charge', label = 'Charge code', required = true },
            { id = 'notes', label = 'Notes', type = 'textarea' },
        })
        if not input then return {} end
        local ok, err = QB.callback.trigger('qbmdt:server:addCriminal', input.citizenid, input.charge, input.notes)
        notify(ok and 'Criminal record saved.' or (err or 'Could not save record.'), ok and 'success' or 'error')
    elseif selectedId == 'medical' then
        local input = form('Medical record', {
            { id = 'citizenid', label = 'Citizen ID', required = true }, { id = 'notes', label = 'Treatment / notes', type = 'textarea', required = true },
        })
        if not input then return {} end
        local ok, err = QB.callback.trigger('qbmdt:server:addMedical', input.citizenid, input.notes)
        notify(ok and 'Medical record saved.' or (err or 'Could not save record.'), ok and 'success' or 'error')
    elseif selectedId == 'analysis' then
        local input = form('Ballistic analysis', { { id = 'caseid', label = 'Casing case ID', required = true } })
        if input then QB.events.trigger('qbmdt:server:beginAnalysis', input.caseid) end
    elseif selectedId == 'firearm' then
        local input = form('Firearm registration', { { id = 'serial', label = 'Gun serial number', required = true } })
        if not input then return {} end
        local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
        notify(row and ('%s — owner %s — licence %s'):format(row.weapon_name, row.owner_citizenid, row.licence_number) or (err or 'No registered sale found.'), row and 'info' or 'error')
    end
    return {}
        end,
    })
    QB.nui.openApp('qbmdt:terminal')
end

RegisterNetEvent('qbmdt:client:open', openTerminal)
RegisterCommand(C.command, function() TriggerServerEvent('qbmdt:server:open') end, false)

local function clearTrainingTargets()
    for _, entity in ipairs(trainingTargets) do QB.entities.remove(entity) end
    trainingTargets = {}
end

RegisterNetEvent('qbmdt:client:weaponLicenceStart', function(settings)
    if training then return end
    training = true
    for _, offset in ipairs(settings.targetOffsets or {}) do
        local entity = QB.entities.create(settings.targetModel, vector4(
            settings.range.x + offset.x,
            settings.range.y + offset.y,
            settings.range.z + offset.z,
            settings.targetHeading
        ), { preset = 'static' })
        if entity then trainingTargets[#trainingTargets + 1] = entity end
    end
    if #trainingTargets == 0 then
        training = false
        QB.events.trigger('qbmdt:server:cancelWeaponLicence')
        return notify('The range targets could not be loaded.', 'error')
    end
    notify(('Fire all %d training rounds, then complete the final handling check.'):format(settings.shots))
end)
RegisterNetEvent('qbmdt:client:weaponLicenceQualification', function(authorization)
    if not training or type(authorization) ~= 'string' then return end
    local definition = C.weaponLicence.qualification
    local result = exports.qblib:minigames_play(definition.game, nil, authorization)
    if result and result.success and result.proof then
        QB.events.trigger('qbmdt:server:completeWeaponLicence', result.proof)
    else
        QB.events.trigger('qbmdt:server:cancelWeaponLicence')
    end
end)
RegisterNetEvent('qbmdt:client:weaponLicenceResult', function(passed, shots)
    if not training then return end
    clearTrainingTargets()
    training = false
    notify(passed and 'Qualification passed. Weapon licence issued.'
        or ('Qualification failed after %d rounds. Try again.'):format(shots or 0), passed and 'success' or 'error')
end)

RegisterNetEvent('qbmdt:client:analysisStage', function(stage, authorization)
    local definition = C.analysis.stages[stage]
    if not definition or type(authorization) ~= 'string' then return end
    local result = exports.qblib:minigames_play(definition.game, nil, authorization)
    if result and result.success and result.proof then
        QB.events.trigger('qbmdt:server:analysisStage', result.proof)
    else
        QB.events.trigger('qbmdt:server:cancelAnalysis')
        notify('Analysis stage failed.', 'error')
    end
end)
RegisterNetEvent('qbmdt:client:analysisComplete', function(result)
    notify(('Case %s linked to %s (%s).'):format(result.caseId, result.weapon, result.weaponSerial), 'success')
end)

exports.qbtarget:addSphereZone({
    coords = C.weaponLicence.range, radius = C.weaponLicence.interactionDistance, distance = C.weaponLicence.interactionDistance,
    options = { { label = 'Start weapon licence range', icon = 'crosshair', onSelect = function() QB.events.trigger('qbmdt:server:startWeaponLicence') end } },
})

for _, record in ipairs(C.firearms.shopRecords) do
    -- A local, invincible clerk makes the configured RP lookup a real person
    -- at the counter. The server still verifies the player's distance before
    -- returning a sale record, so this ped is presentation rather than trust.
    local clerk, err = QB.entities.create('s_m_m_ammucountry', vector4(
        record.coords.x, record.coords.y, record.coords.z - 1.0, record.coords.w
    ), { preset = 'static' })
    if clerk then exports.qbtarget:addEntity(clerk, { { label = record.label, icon = 'file-search', onSelect = function()
            local input = form(record.label, { { id = 'serial', label = 'Gun serial number', required = true } })
            if not input then return end
            local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
            notify(row and ('%s — owner %s'):format(row.weapon_name, row.owner_citizenid) or (err or 'No record found.'), row and 'info' or 'error')
        end } }, 2.0) else print(('^1[qbmdt]^7 records clerk failed to spawn: %s'):format(tostring(err))) end
end
