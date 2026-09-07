local C = Config.mdt
local training, trainingTargets = false, {}
local trainingWeapon, trainingWatch = nil, 0

local function weaponLicenceZoneHeight()
    local zone, lowest = C.weaponLicence.zone, math.huge
    for _, point in ipairs(zone.points) do lowest = math.min(lowest, point.z) end
    return lowest, lowest + zone.thickness
end

local function isInsideWeaponLicenceZone(coords)
    local zone = C.weaponLicence.zone
    local minZ, maxZ = weaponLicenceZoneHeight()
    if coords.z < minZ or coords.z > maxZ then return false end

    local inside, previous = false, zone.points[#zone.points]
    for _, point in ipairs(zone.points) do
        if (point.y > coords.y) ~= (previous.y > coords.y)
            and coords.x < (previous.x - point.x) * (coords.y - point.y) / (previous.y - point.y) + point.x then
            inside = not inside
        end
        previous = point
    end
    return inside
end

local function form(title, fields)
    local result = QB.nui.openInputDialog(fields, title)
    if not result or result.cancelled then return nil end
    return result.values
end
local function notify(message, kind)
    QB.notify.send({ title = 'MDT', message = message, type = kind or 'info' })
end
local function openTerminal(role)
    if role ~= 'police' and role ~= 'medical' and role ~= 'judge' then return end

    local hasCriminalRecords = role == 'police' or role == 'judge'
    local hasMedicalRecords = role == 'medical' or role == 'judge'
    local hasPoliceTools = role == 'police' or role == 'judge'
    local lookupActions = {
        { id = 'person', label = hasMedicalRecords and not hasCriminalRecords and 'Patient lookup' or 'Person & licence lookup', icon = 'contact',
            fields = { { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true } } },
    }
    local navigation = {}

    if hasPoliceTools then
        lookupActions[#lookupActions + 1] = { id = 'vehicle', label = 'Vehicle lookup', icon = 'car-front',
            fields = { { id = 'plate', label = 'Plate', type = 'text', required = true, maxLength = 12 } } }
        lookupActions[#lookupActions + 1] = { id = 'charges', label = 'Available charges', icon = 'scale' }
        lookupActions[#lookupActions + 1] = { id = 'firearm', label = 'Firearm registration lookup', icon = 'crosshair',
            fields = { { id = 'serial', label = 'Gun serial number', type = 'text', required = true } } }
    end

    navigation[#navigation + 1] = {
        id = 'lookup', label = hasMedicalRecords and not hasCriminalRecords and 'Patients' or 'Lookups', icon = 'search',
        content = { title = hasMedicalRecords and not hasCriminalRecords and 'Patient lookup' or 'Records lookup', blocks = { { type = 'actions', actions = lookupActions } } },
    }
    if hasCriminalRecords then
        navigation[#navigation + 1] = {
            id = 'criminal-records', label = 'Criminal records', icon = 'files',
            content = { title = 'Criminal records', blocks = { { type = 'actions', actions = {
                { id = 'criminal', label = 'Add criminal record', icon = 'file-plus', fields = {
                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                    { id = 'charge', label = 'Charge code', type = 'text', required = true },
                    { id = 'notes', label = 'Notes', type = 'textarea', maxLength = 1000 },
                } },
                { id = 'analysis', label = 'Analyse ballistic casing', icon = 'microscope', closeBeforeAction = true,
                    fields = { { id = 'caseid', label = 'Casing case ID', type = 'text', required = true } } },
            } } } },
        }
    end
    if hasMedicalRecords then
        navigation[#navigation + 1] = {
            id = 'medical-records', label = 'Medical records', icon = 'heart-pulse',
            content = { title = 'Medical records', blocks = { { type = 'actions', actions = {
                { id = 'medical', label = 'Add medical record', icon = 'file-plus', fields = {
                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                    { id = 'notes', label = 'Treatment / notes', type = 'textarea', required = true, maxLength = 1000 },
                } },
            } } } },
        }
    end

    local resultView = {
        id = 'results', label = 'Results', icon = 'file-search',
        content = { title = 'Lookup results', blocks = { { type = 'empty', title = 'No result selected',
            description = 'Run a lookup to open its structured record here.', icon = 'search' } } },
    }
    navigation[#navigation + 1] = resultView

    local function showResult(content, notice)
        resultView.content = content
        return {
            update = { navigation = navigation },
            navigate = { viewId = 'results' },
            notice = notice,
        }
    end

    QB.nui.registerApp({
        id = 'qbmdt:terminal',
        title = role == 'medical' and 'Medical Records Terminal' or 'Mobile Data Terminal',
        description = role == 'medical' and 'Patient and medical records' or 'Criminal records and case tools',
        icon = role == 'medical' and 'heart-pulse' or 'monitor-smartphone',
        navigation = navigation,
        footer = 'Records access is verified by the server.',
        onAction = function(selectedId, context)
            local input = type(context and context.value) == 'table' and context.value or {}
            if selectedId == 'criminal' or selectedId == 'analysis' then
                if not hasCriminalRecords then return {} end
            elseif selectedId == 'medical' then
                if not hasMedicalRecords then return {} end
            elseif selectedId == 'vehicle' or selectedId == 'charges' or selectedId == 'firearm' then
                if not hasPoliceTools then return {} end
            end
            if selectedId == 'person' then
        local record, err = QB.callback.trigger('qbmdt:server:person', input.citizenid)
        if not record then return { notice = { tone = 'destructive', message = err or 'No record found.' } } end
        local activity = {}
        for index, row in ipairs(record.firearms or {}) do activity[#activity + 1] = {
            id = 'firearm-' .. index, title = row.weapon_name or 'Registered firearm',
            description = row.serial, icon = 'crosshair', tone = 'primary',
        } end
        for index, row in ipairs(record.criminal or {}) do activity[#activity + 1] = {
            id = 'criminal-' .. index, title = row.charge_code or 'Criminal record',
            description = row.notes, timestamp = tostring(row.created_at or ''), icon = 'scale', tone = 'warning',
        } end
        for index, row in ipairs(record.medical or {}) do activity[#activity + 1] = {
            id = 'medical-' .. index, title = 'Medical record', description = row.notes,
            timestamp = tostring(row.created_at or ''), icon = 'heart-pulse', tone = 'success',
        } end
        return showResult({ title = record.name or input.citizenid, description = 'Person and licence record', blocks = {
            { type = 'details', title = 'Identity and licences', columns = 2, items = {
                { label = 'Citizen ID', value = input.citizenid, icon = 'contact' },
                { label = 'Driver licence', value = record.driverLicensed and 'Valid' or 'Not held',
                    tone = record.driverLicensed and 'success' or 'warning' },
                { label = 'Weapon licence', value = record.weaponLicence or 'Not held', icon = 'shield' },
            } },
            { type = 'timeline', title = 'Record history', items = activity, empty = 'No criminal, medical, or firearm records on file.' },
        } })
    elseif selectedId == 'vehicle' then
        local row, err = QB.callback.trigger('qbmdt:server:vehicle', input.plate)
        if not row then return { notice = { tone = 'destructive', message = err or 'No vehicle found.' } } end
        return showResult({ title = row.plate, description = 'Vehicle registration', blocks = { {
            type = 'details', columns = 2, items = {
                { label = 'Plate', value = row.plate, icon = 'car-front' },
                { label = 'Owner citizen ID', value = row.citizenid, icon = 'contact' },
                { label = 'State', value = row.state, tone = row.state == 'out' and 'warning' or 'neutral' },
            },
        } } })
    elseif selectedId == 'charges' then
        local rows, err = QB.callback.trigger('qbmdt:server:charges')
        if not rows then return { notice = { tone = 'destructive', message = err or 'Not authorised.' } } end
        return showResult({ title = 'Available charges', description = 'Search the server-authorised charge catalogue.', blocks = { {
            type = 'table', id = 'charges', searchable = true, pageSize = 12,
            columns = { { key = 'code', label = 'Code', sortable = true }, { key = 'label', label = 'Charge', sortable = true },
                { key = 'fine', label = 'Fine', align = 'right', sortable = true } },
            rows = rows, empty = 'No charges configured.',
        } } })
    elseif selectedId == 'criminal' then
        local ok, err = QB.callback.trigger('qbmdt:server:addCriminal', input.citizenid, input.charge, input.notes)
        return { notice = { tone = ok and 'success' or 'destructive', message = ok and 'Criminal record saved.' or (err or 'Could not save record.') } }
    elseif selectedId == 'medical' then
        local ok, err = QB.callback.trigger('qbmdt:server:addMedical', input.citizenid, input.notes)
        return { notice = { tone = ok and 'success' or 'destructive', message = ok and 'Medical record saved.' or (err or 'Could not save record.') } }
    elseif selectedId == 'analysis' then
        QB.events.trigger('qbmdt:server:beginAnalysis', input.caseid)
        return { notice = { tone = 'primary', message = 'Ballistic analysis started.' } }
    elseif selectedId == 'firearm' then
        local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
        if not row then return { notice = { tone = 'destructive', message = err or 'No registered sale found.' } } end
        return showResult({ title = row.weapon_name or input.serial, description = 'Registered firearm sale', blocks = { {
            type = 'details', columns = 2, items = {
                { label = 'Serial', value = input.serial, icon = 'crosshair' },
                { label = 'Owner citizen ID', value = row.owner_citizenid, icon = 'contact' },
                { label = 'Licence number', value = row.licence_number or 'Not recorded', icon = 'shield' },
            },
        } } })
    end
    return {}
        end,
    })
    QB.nui.openApp('qbmdt:terminal')
end

RegisterNetEvent('qbmdt:client:open', openTerminal)
RegisterCommand(C.command, function()
    local ok, err = QB.events.trigger('qbmdt:server:open')
    if not ok then notify(err or 'The MDT could not be reached.', 'error') end
end, false)

local function clearTrainingTargets()
    for _, entity in ipairs(trainingTargets) do QB.entities.remove(entity) end
    trainingTargets = {}
end

RegisterNetEvent('qbmdt:client:weaponLicenceStart', function(settings)
    if training then return end
    training = true
    trainingWeapon = type(settings.weapon) == 'string' and settings.weapon or C.weaponLicence.weapon
    trainingWatch = trainingWatch + 1
    local watch = trainingWatch
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
    CreateThread(function()
        while training and trainingWatch == watch do
            Wait(500)
            local position = GetEntityCoords(QB.cache.ped())
            if not isInsideWeaponLicenceZone(position) then
                -- Remove the temporary weapon locally at once, then end the
                -- server-owned session so its inventory state is released too.
                RemoveWeaponFromPed(QB.cache.ped(), GetHashKey(trainingWeapon))
                QB.events.trigger('qbmdt:server:cancelWeaponLicence')
                return notify('You left Ammu-Nation. The range weapon was removed.', 'error')
            end
        end
    end)
    notify(('Fire all %d training rounds to complete the live-fire test.'):format(settings.shots))
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
    trainingWatch = trainingWatch + 1
    trainingWeapon = nil
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

exports.qbtarget:addPolyZone({
    points = C.weaponLicence.zone.points,
    thickness = C.weaponLicence.zone.thickness,
    distance = C.weaponLicence.interactionDistance,
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
