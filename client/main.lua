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
                RemoveWeaponFromPed(QB.cache.ped(), joaat(trainingWeapon))
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
