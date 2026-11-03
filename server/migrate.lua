local COLLATION = 'utf8mb4_unicode_ci'

-- ensureTables never alters existing columns, so tables created before they declared a collation
-- are converted here; information_schema-guarded, a no-op once aligned.
local function alignCollation()
    for _, spec in ipairs(QBMdtSchema) do
        local mismatched, err = Kora.sql.scalar([[SELECT
            (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ? AND table_collation <> ?)
            + (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND collation_name IS NOT NULL AND collation_name <> ?)]],
            { spec.name, COLLATION, spec.name, COLLATION })
        if mismatched == nil then return false, err or 'collation check returned no result' end
        if (tonumber(mismatched) or 0) > 0 then
            local _, alterErr = Kora.sql.execute(('ALTER TABLE `%s` CONVERT TO CHARACTER SET utf8mb4 COLLATE %s'):format(spec.name, COLLATION))
            if alterErr then return false, alterErr end
            print(('^3[qbmdt]^7 converted %s to %s'):format(spec.name, COLLATION))
        end
    end
    return true
end

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

    local aligned, alignErr = alignCollation()
    if not aligned then
        print(('^3[qbmdt]^7 could not align table collation (continuing): %s'):format(tostring(alignErr)))
    end

    local reports, err = Kora.sql.ensureTables(QBMdtSchema)
    if err or not reports then print(('^1[qbmdt]^7 migration failed: %s'):format(tostring(err))); return end
    for _, report in ipairs(reports) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[qbmdt]^7 schema warning on %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    TriggerEvent('qbmdt:server:databaseReady')
end)
