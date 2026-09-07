local function fnv(value)
    local hash, prime = 0xCBF29CE484222325, 0x100000001B3
    for i = 1, #value do hash = (hash ~ string.byte(value, i)) * prime & 0xFFFFFFFFFFFFFFFF end
    return hash
end
local function checksum(value) return ('%016x%016x'):format(fnv(value), fnv(value:reverse())) .. string.rep('0', 32) end

CreateThread(function()
    if not QB.sql.ready(60000) then print('^1[qbmdt]^7 qbsql unavailable; records terminal will not start.'); return end
    local resource = GetCurrentResourceName()
    local migrations = {}
    for version, definition in ipairs({
        { name = 'records', file = 'sql/001_records.sql' },
        { name = 'operations', file = 'sql/002_operations.sql' },
    }) do
        local sql = LoadResourceFile(resource, definition.file)
        if not sql then print('^1[qbmdt]^7 missing ' .. definition.file); return end
        migrations[#migrations + 1] = { version = version, name = definition.name, sql = sql, checksum = checksum(sql) }
    end
    local _, err = QB.sql.migrate(resource, migrations)
    if err then print(('^1[qbmdt]^7 migration failed: %s'):format(tostring(err)))
    else TriggerEvent('qbmdt:server:databaseReady') end
end)
