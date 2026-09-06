local C = Config.mdt
local training, targets = nil, {}

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

local function openTerminal()
    local selected = QB.nui.openMenu({
        { id = 'person', label = 'Person & licence lookup', icon = 'contact' },
        { id = 'vehicle', label = 'Vehicle lookup', icon = 'car-front' },
        { id = 'charges', label = 'Available charges', icon = 'scale' },
        { id = 'criminal', label = 'Add criminal record', icon = 'file-plus' },
        { id = 'medical', label = 'Add medical record', icon = 'heart-pulse' },
        { id = 'firearm', label = 'Firearm registration lookup', icon = 'crosshair' },
        { id = 'analysis', label = 'Analyse ballistic casing', icon = 'microscope' },
    }, 'Mobile data terminal')
    if not selected or selected.cancelled or not selected.selectedId then return end
    if selected.selectedId == 'person' then
        local input = form('Person lookup', { { id = 'citizenid', label = 'Citizen ID', required = true } })
        if not input then return end
        local record, err = QB.callback.trigger('qbmdt:server:person', input.citizenid)
        if not record then return notify(err or 'No record found.', 'error') end
        local detail = ('%s\nDriver licence: %s'):format(record.name, record.driverLicensed and 'valid' or 'not held')
        if record.weaponLicence then detail = detail .. '\nWeapon licence: ' .. record.weaponLicence end
        if record.firearms then detail = detail .. '\nFirearms:\n' .. lines(record.firearms, function(r) return r.weapon_name .. ' — ' .. r.serial end) end
        if record.criminal then detail = detail .. '\nCriminal:\n' .. lines(record.criminal, function(r) return r.charge_code .. ': ' .. (r.notes or '') end) end
        if record.medical then detail = detail .. '\nMedical:\n' .. lines(record.medical, function(r) return r.notes end) end
        return notify(detail)
    end
    if selected.selectedId == 'vehicle' then
        local input = form('Vehicle lookup', { { id = 'plate', label = 'Plate', required = true } })
        if not input then return end
        local row, err = QB.callback.trigger('qbmdt:server:vehicle', input.plate)
        return notify(row and ('%s — owner %s — %s'):format(row.plate, row.citizenid, row.state) or (err or 'No vehicle found.'), row and 'info' or 'error')
    end
    if selected.selectedId == 'charges' then
        local rows, err = QB.callback.trigger('qbmdt:server:charges')
        return notify(rows and lines(rows, function(r) return ('%s: %s ($%d)'):format(r.code, r.label, r.fine) end) or (err or 'Not authorised.'), rows and 'info' or 'error')
    end
    if selected.selectedId == 'criminal' then
        local input = form('Criminal record', {
            { id = 'citizenid', label = 'Citizen ID', required = true }, { id = 'charge', label = 'Charge code', required = true },
            { id = 'notes', label = 'Notes', type = 'textarea' },
        })
        if not input then return end
        local ok, err = QB.callback.trigger('qbmdt:server:addCriminal', input.citizenid, input.charge, input.notes)
        return notify(ok and 'Criminal record saved.' or (err or 'Could not save record.'), ok and 'success' or 'error')
    end
    if selected.selectedId == 'medical' then
        local input = form('Medical record', {
            { id = 'citizenid', label = 'Citizen ID', required = true }, { id = 'notes', label = 'Treatment / notes', type = 'textarea', required = true },
        })
        if not input then return end
        local ok, err = QB.callback.trigger('qbmdt:server:addMedical', input.citizenid, input.notes)
        return notify(ok and 'Medical record saved.' or (err or 'Could not save record.'), ok and 'success' or 'error')
    end
    if selected.selectedId == 'analysis' then
        local input = form('Ballistic analysis', { { id = 'caseid', label = 'Casing case ID', required = true } })
        if input then TriggerServerEvent('qbmdt:server:beginAnalysis', input.caseid) end
        return
    end
    local input = form('Firearm registration', { { id = 'serial', label = 'Gun serial number', required = true } })
    if not input then return end
    local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
    notify(row and ('%s — owner %s — licence %s'):format(row.weapon_name, row.owner_citizenid, row.licence_number) or (err or 'No registered sale found.'), row and 'info' or 'error')
end

RegisterNetEvent('qbmdt:client:open', openTerminal)
RegisterCommand(C.command, function() TriggerServerEvent('qbmdt:server:open') end, false)

local function deleteTargets()
    for _, entity in ipairs(targets) do if DoesEntityExist(entity) then DeleteEntity(entity) end end
    targets = {}
end
RegisterNetEvent('qbmdt:client:weaponLicenceStart', function(settings)
    if training then return end
    training = { shots = 0, settings = settings, weapon = GetHashKey('weapon_pistol') }
    local model = GetHashKey('prop_target_blue_arrow')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end
    for _, offset in ipairs(settings.targetOffsets) do
        local point = settings.range + offset
        local object = CreateObject(model, point.x, point.y, point.z, false, false, false)
        SetEntityHeading(object, 180.0)
        FreezeEntityPosition(object, true)
        targets[#targets + 1] = object
    end
    GiveWeaponToPed(PlayerPedId(), training.weapon, settings.shots, false, true)
    notify('Fire at the range targets. You need ' .. settings.requiredScore .. ' of ' .. settings.shots .. ' accepted hits.')
end)
AddEventHandler('CEventGunShot', function(_, entity)
    if not training or entity ~= PlayerPedId() then return end
    local hit, coords = GetPedLastWeaponImpactCoord(PlayerPedId())
    if not hit then return end
    training.shots = training.shots + 1
    TriggerServerEvent('qbmdt:server:weaponLicenceHit', { x = coords.x, y = coords.y, z = coords.z })
end)
RegisterNetEvent('qbmdt:client:weaponLicenceResult', function(passed, score)
    if not training then return end
    RemoveWeaponFromPed(PlayerPedId(), training.weapon)
    deleteTargets()
    training = nil
    notify(passed and ('Passed: %d hits. Weapon licence issued.'):format(score) or ('Failed: %d hits. Try again.'):format(score), passed and 'success' or 'error')
end)

RegisterNetEvent('qbmdt:client:analysisStage', function(stage)
    local game, opts = ({ 'skillbar', 'circuit', 'pinpad' })[stage], { attempts = 1 }
    if game == 'pinpad' then opts.numbers = tostring(math.random(1000, 9999)) end
    local result = exports.qblib:minigames_play(game, opts)
    if result and result.success and result.proof then TriggerServerEvent('qbmdt:server:analysisStage', result.proof) else notify('Analysis stage failed.', 'error') end
end)
RegisterNetEvent('qbmdt:client:analysisComplete', function(result)
    notify(('Case %s linked to %s (%s).'):format(result.caseId, result.weapon, result.weaponSerial), 'success')
end)

exports.qbtarget:addSphereZone({
    coords = C.weaponLicence.range, radius = C.weaponLicence.interactionDistance, distance = C.weaponLicence.interactionDistance,
    options = { { label = 'Start weapon licence range', icon = 'crosshair', onSelect = function() TriggerServerEvent('qbmdt:server:startWeaponLicence') end } },
})

for _, record in ipairs(C.firearms.shopRecords) do
    -- A local, invincible clerk makes the configured RP lookup a real person
    -- at the counter. The server still verifies the player's distance before
    -- returning a sale record, so this ped is presentation rather than trust.
    local model = GetHashKey('s_m_m_ammucountry')
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(0) end
    local clerk = CreatePed(4, model, record.coords.x, record.coords.y, record.coords.z - 1.0, record.coords.w, false, true)
    FreezeEntityPosition(clerk, true); SetEntityInvincible(clerk, true); SetBlockingOfNonTemporaryEvents(clerk, true)
    exports.qbtarget:addEntity(clerk, { { label = record.label, icon = 'file-search', onSelect = function()
            local input = form(record.label, { { id = 'serial', label = 'Gun serial number', required = true } })
            if not input then return end
            local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
            notify(row and ('%s — owner %s'):format(row.weapon_name, row.owner_citizenid) or (err or 'No record found.'), row and 'info' or 'error')
        end } }, 2.0)
end
