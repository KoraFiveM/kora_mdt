local C = Config.mdt
local training, trainingTargets = false, {}
local trainingWeapon, trainingWatch = nil, 0
local trainingZone, trainingCancelled = nil, false

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
    local result = Kora.nui.openInputDialog(fields, title)
    if not result or result.cancelled then return nil end
    return result.values
end
local function notify(message, kind)
    Kora.notify.send({ title = 'MDT', message = message, type = kind or 'info' })
end
RegisterCommand(C.command, function()
    local ok, err = Kora.events.trigger('kora_mdt:server:open')
    if not ok then notify(err or 'The MDT could not be reached.', 'error') end
end, false)

local function removeTrainingZone()
    if not trainingZone then return end
    trainingZone.remove()
    trainingZone = nil
end

-- Called when the player is found outside the range building. Remove the
-- temporary weapon locally at once, then end the server-owned session so its
-- inventory state is released too. Runs once per session.
local function cancelTrainingOutsideZone(watch)
    if not training or trainingWatch ~= watch or trainingCancelled then return end
    trainingCancelled = true
    RemoveWeaponFromPed(PlayerPedId(), joaat(trainingWeapon))
    Kora.events.trigger('kora_mdt:server:cancelWeaponLicence')
    notify('You left Ammu-Nation. The range weapon was removed.', 'error')
end

local function clearTrainingTargets()
    for _, entity in ipairs(trainingTargets) do Kora.entities.remove(entity) end
    trainingTargets = {}
end

RegisterNetEvent('kora_mdt:client:weaponLicenceStart', function(settings)
    if training then return end
    training = true
    trainingWeapon = type(settings.weapon) == 'string' and settings.weapon or C.weaponLicence.weapon
    trainingWatch = trainingWatch + 1
    local watch = trainingWatch
    for _, offset in ipairs(settings.targetOffsets or {}) do
        local entity = Kora.entities.create(settings.targetModel, vector4(
            settings.range.x + offset.x,
            settings.range.y + offset.y,
            settings.range.z + offset.z,
            settings.targetHeading
        ), { preset = 'static' })
        if entity then trainingTargets[#trainingTargets + 1] = entity end
    end
    if #trainingTargets == 0 then
        training = false
        Kora.events.trigger('kora_mdt:server:cancelWeaponLicence')
        return notify('The range targets could not be loaded.', 'error')
    end
    -- Edge-triggered instead of polling the player's position: the shared
    -- kora_lib zone grid reports the exit, and one delayed check covers a
    -- session that starts while the player is already outside the building.
    trainingCancelled = false
    local licenceZone = C.weaponLicence.zone
    trainingZone = Kora.zones.poly({
        points = licenceZone.points,
        thickness = licenceZone.thickness,
        onExit = function() cancelTrainingOutsideZone(watch) end,
    })
    SetTimeout(500, function()
        if not training or trainingWatch ~= watch then return end
        if not isInsideWeaponLicenceZone(GetEntityCoords(PlayerPedId())) then cancelTrainingOutsideZone(watch) end
    end)
    notify(('Fire all %d training rounds to complete the live-fire test.'):format(settings.shots))
end)
RegisterNetEvent('kora_mdt:client:weaponLicenceQualification', function(authorization)
    if not training or type(authorization) ~= 'string' then return end
    local definition = C.weaponLicence.qualification
    local result = exports.kora_lib:minigames_play(definition.game, nil, authorization)
    if result and result.success and result.proof then
        Kora.events.trigger('kora_mdt:server:completeWeaponLicence', result.proof)
    else
        Kora.events.trigger('kora_mdt:server:cancelWeaponLicence')
    end
end)
RegisterNetEvent('kora_mdt:client:weaponLicenceResult', function(passed, shots)
    if not training then return end
    clearTrainingTargets()
    removeTrainingZone()
    training = false
    trainingWatch = trainingWatch + 1
    trainingWeapon = nil
    notify(passed and 'Qualification passed. Weapon licence issued.'
        or ('Qualification failed after %d rounds. Try again.'):format(shots or 0), passed and 'success' or 'error')
end)

RegisterNetEvent('kora_mdt:client:analysisStage', function(stage, authorization)
    local definition = C.analysis.stages[stage]
    if not definition or type(authorization) ~= 'string' then return end
    local result = exports.kora_lib:minigames_play(definition.game, nil, authorization)
    if result and result.success and result.proof then
        Kora.events.trigger('kora_mdt:server:analysisStage', result.proof)
    else
        Kora.events.trigger('kora_mdt:server:cancelAnalysis')
        notify('Analysis stage failed.', 'error')
    end
end)
RegisterNetEvent('kora_mdt:client:analysisComplete', function(result)
    notify(('Case %s linked to %s (%s).'):format(result.caseId, result.weapon, result.weaponSerial), 'success')
end)

local licenceTarget, recordsClerks = nil, {}

local function registerLicenceTarget()
    if licenceTarget or GetResourceState('kora_target') ~= 'started' then return end
    local licence = C.weaponLicence
    local options = { { label = 'start weapon licence range', icon = 'crosshair', onSelect = function() Kora.events.trigger('kora_mdt:server:startWeaponLicence') end } }

    -- A point keeps the prompt off other targets inside the building (e.g. the vending machine).
    if licence.interactionPoint then
        licenceTarget = exports.kora_target:addSphereZone({
            coords = licence.interactionPoint,
            radius = licence.interactionRadius or 1.5,
            distance = licence.interactionDistance,
            options = options,
        })
        return
    end

    -- Legacy behaviour when no interaction point is configured.
    licenceTarget = exports.kora_target:addPolyZone({
        points = licence.zone.points,
        thickness = licence.zone.thickness,
        distance = licence.interactionDistance,
        options = options,
    })
end

local function registerRecordsClerk(clerk)
    if clerk.target or GetResourceState('kora_target') ~= 'started' then return end
    local record = clerk.record
    clerk.target = exports.kora_target:addEntity(clerk.ped, { { label = record.label, icon = 'file-search', onSelect = function()
        local input = form(record.label, { { id = 'serial', label = 'Gun serial number', type = 'text', required = true } })
        if not input then return end
        local row, err = Kora.callback.trigger('kora_mdt:server:shopFirearm', input.serial)
        notify(row and ('%s — owner %s'):format(row.weapon_name, row.owner_citizenid) or (err or 'No record found.'), row and 'info' or 'error')
    end } }, 2.0)
end

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= 'kora_target' then return end
    -- Registration IDs belong to that target instance and may be reused after restart.
    licenceTarget = nil
    for _, clerk in ipairs(recordsClerks) do clerk.target = nil end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'kora_target' then return end
    registerLicenceTarget()
    for _, clerk in ipairs(recordsClerks) do registerRecordsClerk(clerk) end
end)

registerLicenceTarget()
for _, record in ipairs(C.firearms.shopRecords) do
    -- A local, invincible clerk makes the configured RP lookup a real person
    -- at the counter. The server still verifies the player's distance before
    -- returning a sale record, so this ped is presentation rather than trust.
    local clerk, err = Kora.entities.create('s_m_m_ammucountry', vector4(
        record.coords.x, record.coords.y, record.coords.z - 1.0, record.coords.w
    ), { preset = 'static' })
    if clerk then
        local entry = { ped = clerk, record = record }
        recordsClerks[#recordsClerks + 1] = entry
        registerRecordsClerk(entry)
    else
        print(('^1[kora_mdt]^7 records clerk failed to spawn: %s'):format(tostring(err)))
    end
end
