local h = dofile('test/harness.lua')

local VEC3 = {}
VEC3.__index = VEC3
function _G.vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, VEC3) end
function _G.vector4(x, y, z, w)
    local value = vector3(x, y, z)
    value.w = w
    return value
end

local handlers, serverEvents, removed = {}, {}, {}
local entityFactory = function() return 900 end
local minigameResult = { success = false }

function _G.RegisterNetEvent(name, callback) if callback then handlers[name] = callback end end
function _G.RegisterCommand() end
_G.QB = {
    nui = {
        openInputDialog = function() return nil end,
        registerApp = function() end,
        openApp = function() end,
    },
    notify = { send = function() end },
    callback = { trigger = function() return nil end },
    events = {
        trigger = function(name, ...)
            serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
        end,
    },
    entities = {
        create = function(...) return entityFactory(...) end,
        remove = function(entity) removed[#removed + 1] = entity; return true end,
    },
}

local exportImpls = {
    qbtarget = {
        addSphereZone = function() end,
        addEntity = function() end,
    },
    qblib = {
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
dofile('client/main.lua')

local function settings()
    return {
        targetModel = Config.mdt.weaponLicence.targetModel,
        targetHeading = Config.mdt.weaponLicence.targetHeading,
        range = Config.mdt.weaponLicence.range,
        targetOffsets = Config.mdt.weaponLicence.targetOffsets,
        shots = Config.mdt.weaponLicence.shots,
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

h.test('zero spawned range targets cancels the server session', function()
    reset()
    entityFactory = function() return nil, 'not loaded' end
    handlers['qbmdt:client:weaponLicenceStart'](settings())
    h.assertEqual(#serverEvents, 1)
    h.assertEqual(serverEvents[1].name, 'qbmdt:server:cancelWeaponLicence')
end)

h.test('weapon licence result removes every target through qblib entities', function()
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
