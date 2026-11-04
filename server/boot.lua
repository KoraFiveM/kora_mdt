CreateThread(function()
    if not QB.sql.ready(60000) then print('^1[qbmdt]^7 qbsql unavailable; records terminal will not start.'); return end

    -- kora_core starts before this resource, but its schema setup runs
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

    local reports, err = Kora.sql.ensureTables(QBMdtSchema)
    if err or not reports then print(('^1[qbmdt]^7 schema setup failed: %s'):format(tostring(err))); return end
    for _, report in ipairs(reports) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[qbmdt]^7 schema warning on %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    TriggerEvent('qbmdt:server:databaseReady')
end)
