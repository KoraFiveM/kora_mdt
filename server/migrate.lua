local function fnv(value)
    local hash, prime = 0xCBF29CE484222325, 0x100000001B3
    for i = 1, #value do hash = (hash ~ string.byte(value, i)) * prime & 0xFFFFFFFFFFFFFFFF end
    return hash
end
local function checksum(value) return ('%016x%016x'):format(fnv(value), fnv(value:reverse())) .. string.rep('0', 32) end

CreateThread(function()
    if not QB.sql.ready(60000) then print('^1[qbmdt]^7 qbsql unavailable; records terminal will not start.'); return end

    -- kora_core starts before this resource, but its persistence migrations run
    -- in a thread and may still be adding legacy players columns. Reports that
    -- include a citizen ID query players.deleted_at, so wait for that schema.
    local coreSchemaReady, waited = false, 0
    while waited < 60000 do
        local ok, _, queryErr = pcall(QB.sql.single, 'SELECT `deleted_at` FROM `players` LIMIT 0')
        if ok and not queryErr then coreSchemaReady = true; break end
        Wait(500)
        waited = waited + 500
    end
    if not coreSchemaReady then
        print('^1[qbmdt]^7 kora_core player schema unavailable; report creation will remain disabled.')
        return
    end

    local resource = GetCurrentResourceName()
    local _, err = QB.sql.migrateFiles(resource, {
        { version = 1, name = 'records', file = 'sql/001_records.sql' },
        { version = 2, name = 'operations', file = 'sql/002_operations.sql' },
        { version = 4, name = 'labels', file = 'sql/004_labels.sql' },
    }, checksum)
    if err then print(('^1[qbmdt]^7 migration failed: %s'):format(tostring(err)))
    else TriggerEvent('qbmdt:server:databaseReady') end
end)
