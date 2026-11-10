CreateThread(function()
    if not Kora.sql.ready(60000) then print('^1[kora_mdt]^7 kora_sql unavailable; records terminal will not start.'); return end

    -- kora_core creates the players table in its own schema setup; reports that include a citizen ID query
    -- players.deleted_at, so wait for it before starting.
    if not Kora.sql.awaitTables({ 'players' }, 60000) then
        print('^1[kora_mdt]^7 kora_core player schema unavailable; report creation will remain disabled.')
        return
    end

    local reports, err = Kora.sql.ensureTables(KoraMdtSchema)
    if err or not reports then print(('^1[kora_mdt]^7 schema setup failed: %s'):format(tostring(err))); return end
    for _, report in ipairs(reports) do
        for _, warning in ipairs(report.warnings or {}) do
            print(('^3[kora_mdt]^7 schema warning on %s: %s'):format(tostring(report.table), tostring(warning)))
        end
    end
    TriggerEvent('kora_mdt:server:databaseReady')
end)
