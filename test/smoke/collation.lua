-- Guards against "Illegal mix of collations": qbmdt_* tables must be
-- utf8mb4_unicode_ci (like kora_core's players table) and any join/compare
-- between a qbmdt_* column and an external table must pin COLLATE on both sides.
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
    if not sql:find('qbmdt_', 1, true) then return problems end
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
        if name:find('^qbmdt_') then hasInternal = true else hasExternal = true end
    end
    if not (hasInternal and hasExternal) then return problems end

    if sql:upper():find('%f[%a]UNION%f[%A]') then problems[#problems + 1] = 'UNION across qbmdt and external tables' end
    if sql:upper():find('%f[%a]IN%s*%(%s*SELECT') then problems[#problems + 1] = 'IN (SELECT ...) across qbmdt and external tables' end

    local operand = '(%a%w*)%.`([%w_]+)`([%w_ ]-)' -- alias.`col` [COLLATE x]
    local operandB = '(%a%w*)%.`([%w_]+)`([%w_ ]*)'
    for a, ac, atail, b, bc, btail in sql:gmatch(operand .. '=%s*' .. operandB) do
        local ta, tb = tables[a], tables[b]
        if ta and tb and (ta:find('^qbmdt_') ~= nil) ~= (tb:find('^qbmdt_') ~= nil) then
            local function pinned(tail) return tail:upper():find('^%s*COLLATE%s+' .. COLLATION:upper()) ~= nil end
            if not (pinned(atail) and pinned(btail)) then
                problems[#problems + 1] = ('%s.%s = %s.%s lacks COLLATE %s on both sides'):format(ta, ac, tb, bc, COLLATION)
            end
        end
    end
    return problems
end

h.test('collation audit detects unpinned and accepts pinned qbmdt/external joins', function()
    local bad = 'SELECT 1 FROM `qbmdt_reports` r LEFT JOIN `players` p ON p.`citizenid` = r.`subject_citizenid`'
    h.assertEqual(#audit(bad), 1)
    local oneSide = 'SELECT 1 FROM `qbmdt_reports` r LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid`'
    h.assertEqual(#audit(oneSide), 1)
    local good = 'SELECT 1 FROM `qbmdt_reports` r LEFT JOIN `players` p ON p.`citizenid` COLLATE utf8mb4_unicode_ci = r.`subject_citizenid` COLLATE utf8mb4_unicode_ci'
    h.assertEqual(#audit(good), 0)
    local internal = 'SELECT 1 FROM `qbmdt_reports` r LEFT JOIN `qbmdt_charges` c ON c.`code` = r.`charge_code`'
    h.assertEqual(#audit(internal), 0)
end)

h.test('every qbmdt_* to external-table comparison in server SQL pins the collation on both sides', function()
    local checked = 0
    for _, path in ipairs({ 'server/main.lua', 'server/migrate.lua' }) do
        for _, sql in ipairs(sqlStrings(read(path))) do
            if sql:find('`players`', 1, true) and sql:find('qbmdt_', 1, true) then checked = checked + 1 end
            local problems = audit(sql)
            h.assertEqual(#problems, 0, path .. ': ' .. (problems[1] or '') .. ' in: ' .. sql:gsub('%s+', ' '):sub(1, 90))
        end
    end
    h.assertTrue(checked >= 5, 'expected to audit the report/warrant/case joins against players, saw ' .. checked)
end)

-- 001/002 must stay byte-identical: kora_sql hard-aborts on a checksum change
-- to an already-applied migration, which would stop the MDT from starting.
h.test('001/002 are not touched (checksum safety)', function()
    for _, path in ipairs({ 'sql/001_records.sql', 'sql/002_operations.sql' }) do
        h.assertTrue(read(path):find('utf8mb4_unicode_ci', 1, true) == nil, path .. ' was edited; applied migration checksums would mismatch')
    end
end)

h.test('003 converts every qbmdt_* table and is NOT auto-registered', function()
    local created = {}
    for _, path in ipairs({ 'sql/001_records.sql', 'sql/002_operations.sql' }) do
        for name in read(path):gmatch('CREATE TABLE IF NOT EXISTS `([%w_]+)`') do created[#created + 1] = name end
    end
    h.assertTrue(#created >= 11, 'expected the qbmdt tables from 001/002')
    local migration = read('sql/003_collation.sql')
    for _, name in ipairs(created) do
        h.assertTrue(migration:find('ALTER TABLE `' .. name .. '` CONVERT TO CHARACTER SET utf8mb4 COLLATE ' .. COLLATION .. ';', 1, true) ~= nil,
            '003 does not convert ' .. name)
    end
    h.assertTrue(read('server/migrate.lua'):find('003_collation', 1, true) == nil,
        'kora_sql rejects CONVERT TO as a non retry-safe DDL migration; 003 is a manual migration')
end)

h.report('qbmdt collation')
