local h = dofile('test/harness.lua')

local VEC3 = {}
VEC3.__index = VEC3
function _G.vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, VEC3) end
function _G.vector4(x, y, z, w)
    local value = vector3(x, y, z)
    value.w = w
    return value
end

local handlers, commands, serverEvents, removed, licenceZone = {}, {}, {}, {}, nil
local recordsClerkOption, inputDialog
local hooks, licenceRegistrations, clerkRegistrations, clerkSpawns, nextTargetId = {}, 0, 0, 0, 0
local recordsClerk, recordsDistance
local targetState = 'started'
local registeredApp, openedApp
local entityFactory = function() return 900 end
local minigameResult = { success = false }

function _G.RegisterNetEvent(name, callback) if callback then handlers[name] = callback end end
function _G.RegisterCommand(name, callback) commands[name] = callback end
function _G.AddEventHandler(name, callback) hooks[name] = callback end
function _G.CreateThread() end
function _G.GetResourceState(resource) return resource == 'kora_target' and targetState or 'missing' end
_G.QB = {
    nui = {
        openInputDialog = function(fields, title)
            inputDialog = { fields = fields, title = title }
            return nil
        end,
        registerApp = function(definition) registeredApp = definition end,
        openApp = function(id) openedApp = id end,
    },
    notify = { send = function() end },
    callback = { trigger = function(name)
        if name == 'qbmdt:server:dashboard' then return { recent = {} } end
        if name == 'qbmdt:server:reports' or name == 'qbmdt:server:cases'
            or name == 'qbmdt:server:warrants' or name == 'qbmdt:server:bolos' then return {} end
        return nil
    end },
    events = {
        trigger = function(name, ...)
            serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
        end,
    },
    entities = {
        create = function(model, ...)
            if model == 's_m_m_ammucountry' then clerkSpawns = clerkSpawns + 1 end
            return entityFactory(model, ...)
        end,
        remove = function(entity) removed[#removed + 1] = entity; return true end,
    },
}
-- kora_lib sets QB = Kora (the same table).
_G.Kora = _G.QB

local exportImpls = {
    kora_target = {
        addSphereZone = function(options)
            licenceZone = options
            licenceRegistrations, nextTargetId = licenceRegistrations + 1, nextTargetId + 1
            return nextTargetId
        end,
        addPolyZone = function(options)
            licenceZone = options
            licenceRegistrations, nextTargetId = licenceRegistrations + 1, nextTargetId + 1
            return nextTargetId
        end,
        addEntity = function(entity, options, distance)
            recordsClerk, recordsClerkOption, recordsDistance = entity, options[1], distance
            clerkRegistrations, nextTargetId = clerkRegistrations + 1, nextTargetId + 1
            return nextTargetId
        end,
    },
    kora_lib = {
        minigames_play = function() return minigameResult end,
    },
}
_G.exports = setmetatable({}, {
    __index = function(_, resource)
        return setmetatable({}, {
            __index = function(_, name)
                return function(_, ...)
                    local implementation = exportImpls[resource][name]
                    if implementation then return implementation(...) end
                end
            end,
        })
    end,
})

dofile('config.lua')
dofile('shared/required.lua')
dofile('client/terminal.lua')
dofile(arg[1] or 'client/main.lua')

local function settings()
    return {
        targetModel = Config.mdt.weaponLicence.targetModel,
        targetHeading = Config.mdt.weaponLicence.targetHeading,
        range = Config.mdt.weaponLicence.range,
        targetOffsets = Config.mdt.weaponLicence.targetOffsets,
        shots = Config.mdt.weaponLicence.shots,
        weapon = Config.mdt.weaponLicence.weapon,
    }
end

local function reset()
    serverEvents = {}
    removed = {}
    minigameResult = { success = false }
end

h.test('client contains no hit-coordinate reporting path', function()
    local file = assert(io.open('client/main.lua', 'r'))
    local source = file:read('*a')
    file:close()
    h.assertTrue(source:find('qbmdt:server:weaponLicenceHit', 1, true) == nil)
    h.assertTrue(source:find('GetPedLastWeaponImpactCoord', 1, true) == nil)
end)

local function contains(points, coords)
    local inside, previous = false, points[#points]
    for _, point in ipairs(points) do
        if (point.y > coords.y) ~= (previous.y > coords.y)
            and coords.x < (previous.x - point.x) * (coords.y - point.y) / (previous.y - point.y) + point.x then
            inside = not inside
        end
        previous = point
    end
    return inside
end

h.test('weapon licence target covers the Ammu-Nation building and every firing target', function()
    local definition = Config.mdt.weaponLicence
    local minZ = math.huge
    for _, point in ipairs(definition.zone.points) do minZ = math.min(minZ, point.z) end
    local maxZ = minZ + definition.zone.thickness
    h.assertTrue(contains(definition.zone.points, definition.range), 'the counter marker must be inside the target zone')
    for index, offset in ipairs(definition.targetOffsets) do
        local target = vector3(definition.range.x + offset.x, definition.range.y + offset.y, definition.range.z + offset.z)
        h.assertTrue(contains(definition.zone.points, target), ('target %d must be inside the building target zone'):format(index))
        h.assertTrue(target.z >= minZ and target.z <= maxZ,
            ('target %d must be inside the building height band'):format(index))
    end
end)

h.test('/mdt enters through the authenticated kora_lib event channel', function()
    reset()
    commands[Config.mdt.command]()
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:open')
end)

h.test('police terminal exposes operational views with interactive tables', function()
    reset()
    handlers['qbmdt:client:open']('police')
    h.assertEqual(openedApp, 'qbmdt:terminal')
    h.assertEqual(registeredApp.navigation[1].id, 'dashboard')
    local byId = {}
    for _, view in ipairs(registeredApp.navigation) do byId[view.id] = view end
    for _, id in ipairs({ 'search', 'reports', 'cases', 'warrants', 'bolos', 'tools', 'results' }) do
        h.assertTrue(byId[id] ~= nil, id .. ' view must be present')
    end
    h.assertEqual(byId.reports.content.blocks[2].action, 'report:select')
    h.assertEqual(byId.cases.content.blocks[2].action, 'case:select')
    h.assertEqual(byId.warrants.content.blocks[2].action, 'warrant:select')
    h.assertEqual(byId.bolos.content.blocks[2].action, 'bolo:select')
end)

h.test('Ammu-Nation records clerk opens a typed serial-number field', function()
    inputDialog = nil
    recordsClerkOption.onSelect()
    h.assertEqual(inputDialog.title, Config.mdt.firearms.shopRecords[1].label)
    h.assertEqual(inputDialog.fields[1].id, 'serial')
    h.assertEqual(inputDialog.fields[1].type, 'text')
    h.assertTrue(inputDialog.fields[1].required)
end)

h.test('qbtarget restart restores range and clerk options without respawning the clerk', function()
    h.assertTrue(type(hooks.onClientResourceStart) == 'function', 'dependency start listener must exist')
    h.assertTrue(type(hooks.onClientResourceStop) == 'function', 'dependency stop listener must exist')
    local ped, spawns = recordsClerk, clerkSpawns
    local beforeZones, beforeClerks = licenceRegistrations, clerkRegistrations
    hooks.onClientResourceStop('kora_target')
    licenceZone, recordsClerkOption = nil, nil -- Dependency registrations are fresh after restart.
    hooks.onClientResourceStart('kora_target')
    h.assertEqual(licenceRegistrations, beforeZones + 1)
    h.assertEqual(clerkRegistrations, beforeClerks + #Config.mdt.firearms.shopRecords)
    h.assertEqual(recordsClerk, ped)
    h.assertEqual(clerkSpawns, spawns)
    h.assertEqual(licenceZone.coords, Config.mdt.weaponLicence.interactionPoint)
    h.assertEqual(licenceZone.radius, Config.mdt.weaponLicence.interactionRadius)
    h.assertTrue(licenceZone.points == nil, 'point mode must not register the building polygon')
    h.assertEqual(licenceZone.distance, Config.mdt.weaponLicence.interactionDistance)
    h.assertEqual(licenceZone.options[1].label, 'start weapon licence range')
    h.assertEqual(licenceZone.options[1].icon, 'crosshair')
    h.assertEqual(recordsClerkOption.label, Config.mdt.firearms.shopRecords[1].label)
    h.assertEqual(recordsClerkOption.icon, 'file-search')
    h.assertEqual(recordsDistance, 2.0)
    reset()
    licenceZone.options[1].onSelect()
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:startWeaponLicence')
    inputDialog = nil
    recordsClerkOption.onSelect()
    h.assertEqual(inputDialog.title, Config.mdt.firearms.shopRecords[1].label)
    h.assertEqual(inputDialog.fields[1].id, 'serial')
end)

h.test('without an interaction point the licence target falls back to the building polygon', function()
    local licence = Config.mdt.weaponLicence
    local point = licence.interactionPoint
    licence.interactionPoint = nil
    hooks.onClientResourceStop('kora_target')
    licenceZone = nil
    hooks.onClientResourceStart('kora_target')
    licence.interactionPoint = point
    h.assertEqual(licenceZone.points, licence.zone.points)
    h.assertEqual(licenceZone.thickness, licence.zone.thickness)
    h.assertEqual(licenceZone.distance, licence.interactionDistance)
    h.assertEqual(licenceZone.options[1].label, 'start weapon licence range')
    h.assertTrue(licenceZone.coords == nil)
end)

h.test('interaction point lies inside the building polygon', function()
    local licence = Config.mdt.weaponLicence
    h.assertTrue(contains(licence.zone.points, licence.interactionPoint), 'interaction point must be inside the zone')
end)

h.test('target recovery ignores foreign and repeated starts but supports another restart', function()
    h.assertTrue(type(hooks.onClientResourceStart) == 'function')
    local beforeZones, beforeClerks, spawns = licenceRegistrations, clerkRegistrations, clerkSpawns
    hooks.onClientResourceStart('foreign')
    hooks.onClientResourceStop('foreign')
    hooks.onClientResourceStart('kora_mdt')
    hooks.onClientResourceStart('kora_target')
    h.assertEqual(licenceRegistrations, beforeZones)
    h.assertEqual(clerkRegistrations, beforeClerks)
    hooks.onClientResourceStop('kora_target')
    hooks.onClientResourceStart('kora_target')
    hooks.onClientResourceStart('kora_target')
    h.assertEqual(licenceRegistrations, beforeZones + 1)
    h.assertEqual(clerkRegistrations, beforeClerks + #Config.mdt.firearms.shopRecords)
    h.assertEqual(clerkSpawns, spawns)
end)

h.test('target registration waits while the dependency is unavailable', function()
    h.assertTrue(type(hooks.onClientResourceStart) == 'function')
    local beforeZones, beforeClerks, spawns = licenceRegistrations, clerkRegistrations, clerkSpawns
    targetState = 'stopped'
    hooks.onClientResourceStop('kora_target')
    hooks.onClientResourceStart('kora_target')
    h.assertEqual(licenceRegistrations, beforeZones)
    h.assertEqual(clerkRegistrations, beforeClerks)
    targetState = 'started'
    hooks.onClientResourceStart('kora_target')
    h.assertEqual(licenceRegistrations, beforeZones + 1)
    h.assertEqual(clerkRegistrations, beforeClerks + #Config.mdt.firearms.shopRecords)
    h.assertEqual(clerkSpawns, spawns)
end)

h.test('zero spawned range targets cancels the server session', function()
    reset()
    entityFactory = function() return nil, 'not loaded' end
    handlers['qbmdt:client:weaponLicenceStart'](settings())
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:cancelWeaponLicence')
end)

h.test('weapon licence result removes every target through kora_lib entities', function()
    reset()
    local nextEntity = 100
    entityFactory = function()
        nextEntity = nextEntity + 1
        return nextEntity
    end
    handlers['qbmdt:client:weaponLicenceStart'](settings())
    handlers['qbmdt:client:weaponLicenceResult'](false, 3)
    h.assertEqual(#removed, #Config.mdt.weaponLicence.targetOffsets)
    h.assertEqual(removed[1], 101)
    h.assertEqual(removed[#removed], 103)
end)

h.test('failed qualification cancels instead of submitting a result', function()
    reset()
    entityFactory = function() return 200 end
    handlers['qbmdt:client:weaponLicenceStart'](settings())
    minigameResult = { success = false }
    handlers['qbmdt:client:weaponLicenceQualification']('authorization-1')
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:cancelWeaponLicence')
end)

h.test('successful qualification submits only its proof', function()
    reset()
    -- The preceding failure leaves client training active until the server's
    -- result arrives, so emulate that acknowledgement before starting again.
    handlers['qbmdt:client:weaponLicenceResult'](false, 0)
    entityFactory = function() return 300 end
    handlers['qbmdt:client:weaponLicenceStart'](settings())
    minigameResult = { success = true, proof = 'proof-1' }
    handlers['qbmdt:client:weaponLicenceQualification']('authorization-2')
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:completeWeaponLicence')
    h.assertEqual(serverEvents[1].args[1], 'proof-1')
    h.assertEqual(serverEvents[1].args[2], nil)
end)

h.report('qbmdt client')
