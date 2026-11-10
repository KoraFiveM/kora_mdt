-- Guards against "Illegal mix of collations": kora_mdt_* tables must be
-- utf8mb4_unicode_ci (like kora_core's players table) and any join/compare
-- between a kora_mdt_* column and an external table must pin COLLATE on both sides.
local h = dofile('test/harness.lua')

local COLLATION = 'utf8mb4_unicode_ci'

local function read(path)
    local file = assert(io.open(path, 'rb'), 'cannot open ' .. path)
    local text = file:read('a')
    file:close()
    return text
end

local function sqlStrings(source)
    local found = {}
    for body in source:gmatch('%[%[(.-)%]%]') do found[#found + 1] = body end
    for _, quote in ipairs({ "'", '"' }) do
        for body in source:gmatch(quote .. '([^' .. quote .. '\n]*)' .. quote) do
            if body:find('`', 1, true) and body:upper():find('SELECT', 1, true) then found[#found + 1] = body end
        end
    end
    return found
end

local function audit(sql)
    local problems = {}
    if not sql:find('kora_mdt_', 1, true) then return problems end
    local tables = {}
    for _, keyword in ipairs({ 'FROM', 'JOIN' }) do
        for name, alias in sql:gmatch(keyword .. '%s+`([%w_]+)`%s+(%a%w*)') do
            if alias:upper() ~= 'LEFT' and alias:upper() ~= 'ON' and alias:upper() ~= 'WHERE' and alias:upper() ~= 'JOIN' then
                tables[alias] = name
            end
        end
        for name in sql:gmatch(keyword .. '%s+`([%w_]+)`') do tables[name] = tables[name] or name end
    end
    local hasInternal, hasExternal = false, false
    for _, name in pairs(tables) do
        if name:find('^kora_mdt_') then hasInternal = true else hasExternal = true end
    end
    if not (hasInternal and hasExternal) then return problems end

    if sql:upper():find('%f[%a]UNION%f[%A]') then problems[#problems + 1] = 'UNION across kora_mdt and external tables' end
    if sql:upper():find('%f[%a]IN%s*%(%s*SELECT') then problems[#problems + 1] = 'IN (SELECT ...) across kora_mdt and external tables' end

    local operand = '(%a%w*)%.`([%w_]+)`([%w_ ]-)' -- alias.`col` [COLLATE x]
    local operandB = '(%a%w*)%.`([%w_]+)`([%w_ ]*)'
    for a, ac, atail, b, bc, btail in sql:gmatch(operand .. '=%s*' .. operandB) do
        local ta, tb = tables[a], tables[b]
        if ta and tb and (ta:find('^kora_mdt_') ~= nil) ~= (tb:find('^kora_mdt_') ~= nil) then
            local function pinned(tail) return tail:upper():find('^%s*COLLATE%s+' .. COLLATION:upper()) ~= nil end
            if not (pinned(atail) and pinned(btail)) then
                problems[#problems + 1] = ('%s.%s = %s.%s lacks COLLATE %s on both sides'):format(ta, ac, tb, bc, COLLATION)
            end
        end
    end
    return problems
end

h.test('collation audit detects unpinned and accepts pinned kora_mdt/external joins', function()
    local bad = 'SELECT 1 FROM `kora_mdt_reports` r LEFT JOIN `players` p ON p.`citizenid` = r.`subject_citizenid`'
    h.assertEqual(#audit(bad), 1)
    local oneSide = 'SELECT 1 FROM `kora_mdt_reports` r LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid`'
    h.assertEqual(#audit(oneSide), 1)
    local good = 'SELECT 1 FROM `kora_mdt_reports` r LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid` COLLATE utf8mb4_unicode_ci'
    h.assertEqual(#audit(good), 0)
    local internal = 'SELECT 1 FROM `kora_mdt_reports` r LEFT JOIN `kora_mdt_charges` c ON c.`code` = r.`charge_code`'
    h.assertEqual(#audit(internal), 0)
end)

h.test('every kora_mdt_* to external-table comparison in server SQL pins the collation on both sides', function()
    local checked = 0
    for _, path in ipairs({ 'server/main.lua', 'server/boot.lua' }) do
        for _, sql in ipairs(sqlStrings(read(path))) do
            if sql:find('`players`', 1, true) and sql:find('kora_mdt_', 1, true) then checked = checked + 1 end
            local problems = audit(sql)
            h.assertEqual(#problems, 0, path .. ': ' .. (problems[1] or '') .. ' in: ' .. sql:gsub('%s+', ' '):sub(1, 90))
        end
    end
    h.assertTrue(checked >= 5, 'expected to audit the report/warrant/case joins against players, saw ' .. checked)
end)

h.test('schema declares every kora_mdt_* table with the unicode collation', function()
    _G.Kora = _G.Kora or { sql = { NULL = '\0kora_sql:null\0' } }
    dofile('server/schema.lua')
    h.assertTrue(#KoraMdtSchema >= 11, 'expected the kora_mdt tables in KoraMdtSchema')
    local names = {}
    for _, spec in ipairs(KoraMdtSchema) do
        names[spec.name] = true
        h.assertEqual(spec.collate, COLLATION, spec.name .. ' must declare ' .. COLLATION)
        h.assertTrue(spec.primary ~= nil, spec.name .. ' needs a primary key')
    end
    for _, name in ipairs({ 'kora_mdt_licences', 'kora_mdt_firearms', 'kora_mdt_charges', 'kora_mdt_criminal_records',
        'kora_mdt_medical_records', 'kora_mdt_reports', 'kora_mdt_cases', 'kora_mdt_case_reports', 'kora_mdt_warrants',
        'kora_mdt_bolos', 'kora_mdt_audit_log' }) do
        h.assertTrue(names[name], 'schema is missing ' .. name)
    end
end)

h.test('startup only applies the schema: no migrations, conversions or sql files', function()
    local source = read('server/boot.lua')
    h.assertTrue(source:find('ensureTables(KoraMdtSchema)', 1, true) ~= nil, 'boot.lua must call ensureTables')
    for _, banned in ipairs({ 'migrateFiles', 'Kora.sql.migrate', 'ALTER TABLE', 'CONVERT TO' }) do
        h.assertTrue(source:find(banned, 1, true) == nil, 'boot.lua must not contain ' .. banned)
    end
    h.assertTrue(source:find("awaitTables({ 'players' }", 1, true) ~= nil and source:find('LIMIT 0', 1, true) == nil, 'boot waits for core players table instead of polling')
    h.assertTrue(read('fxmanifest.lua'):find("'server/schema.lua', 'server/boot.lua'", 1, true) ~= nil, 'schema must load before boot.lua')
end)

h.report('kora_mdt collation')
