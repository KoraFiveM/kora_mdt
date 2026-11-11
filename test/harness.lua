local harness = { total = 0, failed = 0 }

function harness.test(name, fn)
    harness.total = harness.total + 1
    local ok, err = pcall(fn)
    if ok then
        print('ok - ' .. name)
    else
        harness.failed = harness.failed + 1
        print('not ok - ' .. name .. ': ' .. tostring(err))
    end
end

function harness.assertTrue(value, message)
    if value ~= true then error(message or 'expected true', 2) end
end

function harness.assertFalse(value, message)
    if value ~= false then error(message or 'expected false', 2) end
end

function harness.assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or 'values differ') .. (': expected %s, got %s'):format(tostring(expected), tostring(actual)), 2)
    end
end

function harness.assertTableEqual(actual, expected, message)
    for key, value in pairs(expected) do
        if actual[key] ~= value then
            error((message or 'tables differ') .. (': key %s expected %s, got %s'):format(
                tostring(key), tostring(value), tostring(actual[key])), 2)
        end
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            error((message or 'tables differ') .. ': unexpected key ' .. tostring(key), 2)
        end
    end
end

function harness.report(name)
    print(('%s: %d passed, %d failed'):format(name, harness.total - harness.failed, harness.failed))
    if harness.failed > 0 then os.exit(1) end
end

return harness
