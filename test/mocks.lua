local M = {}

function M.install()
    local handle = {
        players = {},
        clientEvents = {},
        netHandlers = {},
        eventHandlers = {},
        timeouts = {},
        notifications = {},
        starts = {},
        stops = {},
        authorizations = {},
        consumes = {},
        licenceRows = {},
        metadataWrites = {},
        evidence = {},
        ballisticCasings = {},
        sqlWrites = 0,
        sqlInserts = {},
        sqlUpdates = {},
        sqlSingle = nil,
        sqlQuery = nil,
        clock = 0,
        startTrainingResult = true,
        startTrainingError = nil,
        authorizeEnabled = true,
        metadataResult = true,
    }

    local VEC3 = {}
    VEC3.__index = VEC3
    VEC3.__sub = function(a, b)
        return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, VEC3)
    end
    VEC3.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
    function _G.vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, VEC3) end
    function _G.vector4(x, y, z, w)
        local value = vector3(x, y, z)
        value.w = w
        return value
    end

    _G.source = nil
    function _G.RegisterNetEvent(name, callback)
        if callback then handle.netHandlers[name] = callback end
    end
    function _G.AddEventHandler(name, callback) handle.eventHandlers[name] = callback end
    function _G.TriggerClientEvent(name, target, ...)
        handle.clientEvents[#handle.clientEvents + 1] = { name = name, target = target, args = { ... } }
    end
    function _G.CreateThread(fn) fn() end
    function _G.SetTimeout(delay, callback)
        handle.timeouts[#handle.timeouts + 1] = { delay = delay, callback = callback }
        return #handle.timeouts
    end
    function _G.GetGameTimer() return handle.clock end
    function _G.GetPlayerPed(src) return handle.players[src] and src or 0 end
    function _G.GetEntityCoords(ped)
        return handle.players[ped] and handle.players[ped].coords or vector3(10000.0, 10000.0, 10000.0)
    end
    function _G.GetPlayerRoutingBucket(src) return handle.players[src] and handle.players[src].bucket or 0 end
    function _G.GetCurrentResourceName() return 'qbmdt' end

    function handle.ensurePlayer(src, overrides)
        overrides = overrides or {}
        local citizenid = overrides.citizenid or ('CID%06d'):format(src)
        handle.players[src] = {
            citizenid = citizenid,
            metadata = overrides.metadata or { licences = {} },
            job = overrides.job or { name = 'police', onduty = true },
            coords = overrides.coords or vector3(22.5, -1104.5, 29.8),
            bucket = overrides.bucket or 0,
        }
        return handle.players[src]
    end

    function handle.net(name, src, ...)
        local registered = QB.events.registry[name]
        if registered then return registered.handler(src, ...) end
        local callback = assert(handle.netHandlers[name], 'missing event handler ' .. name)
        local previous = _G.source
        _G.source = src
        callback(...)
        _G.source = previous
    end

    function handle.event(name, src, ...)
        local callback = assert(handle.eventHandlers[name], 'missing event handler ' .. name)
        if name == 'playerDropped' then
            local previous = _G.source
            _G.source = src
            callback(...)
            _G.source = previous
        else
            callback(src, ...)
        end
    end

    function handle.eventsNamed(name, target)
        local events = {}
        for _, event in ipairs(handle.clientEvents) do
            if event.name == name and (target == nil or event.target == target) then events[#events + 1] = event end
        end
        return events
    end

    local nextAuthorization, nextProof = 0, 0
    local issuedAuthorizations, proofs = {}, {}
    _G.QB = {
        callback = {
            registry = {},
            register = function(name, callback) QB.callback.registry[name] = callback end,
        },
        events = {
            registry = {},
            register = function(name, callback, options)
                QB.events.registry[name] = { handler = callback, options = options }
            end,
        },
        minigames = {
            authorizeProof = function(src, game, opts)
                if not handle.authorizeEnabled then return nil end
                nextAuthorization = nextAuthorization + 1
                local token = ('authorization-%d'):format(nextAuthorization)
                local record = { token = token, src = src, game = game, opts = opts }
                issuedAuthorizations[token] = record
                handle.authorizations[#handle.authorizations + 1] = record
                return token
            end,
            consumeProof = function(src, proof, game, authorization)
                handle.consumes[#handle.consumes + 1] = {
                    src = src, proof = proof, game = game, authorization = authorization,
                }
                local record = proofs[proof]
                if not record or record.src ~= src or record.game ~= game or record.authorization ~= authorization then
                    return false
                end
                proofs[proof] = nil
                return true
            end,
        },
        notify = {
            send = function(src, payload)
                handle.notifications[#handle.notifications + 1] = { src = src, payload = payload }
            end,
        },
        sql = {
            single = function(query, params)
                if handle.sqlSingle then return handle.sqlSingle(query, params) end
                if query:find('qbmdt_licences', 1, true) then
                    local number = handle.licenceRows[params[1]]
                    return number and { licence_number = number } or nil
                end
                return nil
            end,
            query = function(query, params)
                if handle.sqlQuery then return handle.sqlQuery(query, params) end
                return {}
            end,
            execute = function(query, params)
                if query:find('qbmdt_licences', 1, true) then
                    handle.sqlWrites = handle.sqlWrites + 1
                    if handle.onLicenceWrite then handle.onLicenceWrite(params) end
                    handle.licenceRows[params[1]] = params[3]
                end
                return 1
            end,
            insert = function(query, params)
                handle.sqlInserts[#handle.sqlInserts + 1] = { query = query, params = params }
                return #handle.sqlInserts
            end,
            update = function(query, params)
                handle.sqlUpdates[#handle.sqlUpdates + 1] = { query = query, params = params }
                return 1
            end,
        },
    }

    function handle.issueProof(src, game, authorization)
        nextProof = nextProof + 1
        local token = ('proof-%d'):format(nextProof)
        proofs[token] = { src = src, game = game, authorization = authorization }
        return token
    end

    local exportImpls = { qbcore = {}, qbinventory = {}, qbpolice = {} }
    _G.exports = setmetatable({}, {
        __call = function() end,
        __index = function(_, resource)
            return setmetatable({}, {
                __index = function(_, name)
                    return function(_, ...)
                        local implementation = exportImpls[resource][name]
                        if implementation then return implementation(...) end
                        return nil
                    end
                end,
            })
        end,
    })

    function exportImpls.qbcore.getPlayerData(src) return handle.players[src] end
    function exportImpls.qbcore.getJob(src) return handle.players[src] and handle.players[src].job end
    function exportImpls.qbcore.setMetaData(src, key, value)
        if not handle.metadataResult then return false end
        local player = handle.players[src]
        if not player then return false end
        player.metadata[key] = value
        handle.metadataWrites[#handle.metadataWrites + 1] = { src = src, key = key, value = value }
        return true
    end
    function exportImpls.qbcore.getShared(kind, item)
        return kind == 'weapons' and type(item) == 'string' and item:find('weapon_', 1, true) == 1 or nil
    end
    function exportImpls.qbinventory.RegisterHook() return true end
    function exportImpls.qbinventory.GetItemsByName(src)
        local caseId = handle.evidence[src]
        return caseId and { { info = { caseId = caseId } } } or {}
    end
    function exportImpls.qbinventory.StartTrainingWeapon(src, weapon, shots)
        handle.starts[#handle.starts + 1] = { src = src, weapon = weapon, shots = shots }
        return handle.startTrainingResult, handle.startTrainingError
    end
    function exportImpls.qbinventory.StopTrainingWeapon(src)
        handle.stops[#handle.stops + 1] = src
        return true
    end
    function exportImpls.qbpolice.GetBallisticCasing(caseId) return handle.ballisticCasings[caseId] end

    return handle
end

return M
