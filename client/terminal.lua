local C = Config.mdt

local function action(id, label, icon, fields, variant)
    return { id = id, label = label, icon = icon, fields = fields, variant = variant }
end

local function message(ok, success, failure)
    return { notice = { tone = ok and 'success' or 'destructive', message = ok and success or (failure or 'The action failed.') } }
end

-- Times arrive from the server already formatted; never stringify anything else
-- (a raw table would render as 'table: 0x...').
local function when(value, empty)
    if type(value) == 'string' and value ~= '' then return value end
    return empty
end

local function statusCell(value)
    local tone = 'neutral'
    if value == 'active' or value == 'open' or value == 'investigating' or value == 'high' or value == 'critical' then
        tone = 'warning'
    elseif value == 'closed' or value == 'served' or value == 'resolved' then
        tone = 'success'
    end
    return { label = tostring(value or 'unknown'), badge = true, tone = tone }
end

local function openTerminal(role, policeBoss)
    if role ~= 'police' and role ~= 'medical' and role ~= 'judge' then return end

    local criminalAccess = role == 'police' or role == 'judge'
    local medicalAccess = role == 'medical' or role == 'judge'
    local policeAccess = criminalAccess
    policeBoss = role == 'police' and policeBoss == true
    local function req(form, field) return MdtRequired.isRequired(form, field) end
    local chargeOptions = {}
    local reportOptions = {}
    local caseOptions = {}
    local selectedCharge
    local function setChargeOptions(rows)
        for i = #chargeOptions, 1, -1 do chargeOptions[i] = nil end
        for _, charge in ipairs(rows) do chargeOptions[#chargeOptions + 1] = { value = charge.label, label = charge.label } end
    end
    local function chargeManagementContent(rows)
        return { title = 'Charge management', description = 'Create charges for the criminal record and report tools.', blocks = {
            { type = 'actions', actions = {
                action('charge:create', 'Create charge', 'plus', {
                    { id = 'code', label = 'Charge code', type = 'text', required = true, maxLength = 32 },
                    { id = 'label', label = 'Charge name', type = 'text', required = true, maxLength = 128 },
                    { id = 'fine', label = 'Fine', type = 'number', required = true, min = 0, max = 2000000000 },
                }, 'primary'), action('charge:refresh', 'Refresh charges', 'refresh-cw'),
            } },
            { type = 'table', id = 'managed-charges', searchable = true, pageSize = 12,
                columns = { { key = 'label', label = 'Charge', sortable = true },
                    { key = 'fine', label = 'Fine', align = 'right', sortable = true },
                    { key = 'active', label = 'Active', sortable = true } },
                rows = rows, empty = 'No charges configured.',
                action = 'charge:select', idKey = 'code' },
        } }
    end
    local function chargeContent(charge)
        return {
            title = charge.label,
            description = 'Charge code: ' .. tostring(charge.code),
            actions = { action('charge:edit', 'Edit charge', 'pencil', {
                { id = 'label', label = 'Charge name', type = 'text', required = true, maxLength = 128, default = charge.label },
                { id = 'fine', label = 'Fine', type = 'number', required = true, min = 0, max = 2000000000, default = charge.fine },
            }, 'primary') },
            blocks = { { type = 'details', columns = 2, items = {
                { label = 'Code', value = tostring(charge.code) },
                { label = 'Charge', value = tostring(charge.label) },
                { label = 'Fine', value = tostring(charge.fine) },
                { label = 'Active', value = tostring(charge.active == true or charge.active == 1) },
            } } },
        }
    end
    if policeAccess then
        setChargeOptions(QB.callback.trigger('qbmdt:server:charges') or {})
        local reports = QB.callback.trigger('qbmdt:server:reportOptions') or {}
        for _, report in ipairs(reports) do
            reportOptions[#reportOptions + 1] = {
                value = tostring(report.id),
                label = ('%s - %s'):format(report.title or 'Untitled', report.subject or 'Unknown'),
            }
        end
        local cases = QB.callback.trigger('qbmdt:server:cases') or {}
        for _, case in ipairs(cases) do
            caseOptions[#caseOptions + 1] = {
                value = tostring(case.id),
                label = ('#%s - %s'):format(case.id, case.title or 'Untitled'),
            }
        end
    end
    local navigation = {}
    local selectedReport, selectedCase, selectedWarrant, selectedBolo

    local resultView = {
        id = 'results', label = 'Record', icon = 'file-search',
        content = { title = 'Record viewer', blocks = { { type = 'empty', title = 'No record selected',
            description = 'Search for a person, vehicle, report, warrant, or BOLO.', icon = 'search' } } },
    }

    local function findView(id)
        for _, view in ipairs(navigation) do if view.id == id then return view end end
    end

    local function update(viewId, content, notice, tabId)
        local view = findView(viewId)
        if view and content then view.content = content end
        return { update = { navigation = navigation }, navigate = { viewId = viewId, tabId = tabId }, notice = notice }
    end

    local function showResult(content, notice)
        if resultView.tabs then
            for _, tab in ipairs(resultView.tabs) do
                if tab.id == 'record' then
                    tab.content = content
                    return update('results', nil, notice, 'record')
                end
            end
        end
        resultView.content = content
        return update('results', nil, notice)
    end

    local function caseContent(row)
        local caseActions = { {
            id = 'case:link-report', label = 'Add report', icon = 'plus', fields = {
                { id = 'report_id', label = 'Search reports', type = 'select', searchable = true, required = true,
                    options = reportOptions, placeholder = 'Search by title or subject...' },
            },
        } }
        if row.status == 'open' then
            caseActions[#caseActions + 1] = { id = 'case:investigate', label = 'Begin investigation', icon = 'search', variant = 'primary' }
        end
        if row.status ~= 'closed' then
            caseActions[#caseActions + 1] = { id = 'case:close', label = 'Close case', icon = 'check-circle', variant = 'primary', confirm = 'Close this investigation?' }
        else
            caseActions[#caseActions + 1] = { id = 'case:reopen', label = 'Reopen case', icon = 'rotate-ccw', confirm = 'Reopen this investigation?' }
        end
        local linked = {}
        for _, report in ipairs(row.reports or {}) do linked[#linked + 1] = {
            id = tostring(report.id), title = ('Report #%s · %s'):format(tostring(report.id), tostring(report.title or 'Untitled')),
            description = tostring(report.subject_citizenid or report.subject_text or 'Unknown'), timestamp = when(report.updated_at, ''),
            icon = 'file-text', tone = tostring(report.status) == 'open' and 'warning' or 'neutral',
            actions = { { id = 'report:open-linked', label = 'Open report', icon = 'file-search' } },
        } end
        return { title = ('Case #%s · %s'):format(row.id, row.title), description = tostring(row.summary or ''),
            actions = caseActions, blocks = {
                { type = 'details', title = 'Investigation', columns = 2, items = {
                    { label = 'status', value = tostring(row.status or 'unknown') }, { label = 'Priority', value = tostring(row.priority or 'normal') },
                    { label = 'Lead', value = tostring(row.lead_name or row.lead_citizenid or 'Unknown') }, { label = 'Opened', value = when(row.created_at, '—') },
                } }, { type = 'timeline', title = 'Linked reports', items = linked, empty = 'No reports linked to this case.' },
            } }
    end

    local function reportContent(row)
        local actions = {}
        if row.status == 'open' then actions[1] = { id = 'report:close', label = 'Close report', icon = 'check-circle', variant = 'primary', confirm = 'Close this incident report?' } end
        return { title = ('Report #%s · %s'):format(row.id, tostring(row.title or 'Untitled')),
            description = tostring(row.narrative or ''), actions = actions, blocks = {
            { type = 'details', title = 'Report details', columns = 2, items = {
                { label = 'Status', value = tostring(row.status or 'unknown') },
                { label = 'Subject', value = tostring(row.subject_name or row.subject_citizenid or row.subject_text or 'Unknown') },
                { label = 'Charge', value = tostring(row.charge_label or row.charge_text or 'None') },
                { label = 'Fine', value = tostring(row.fine or '—') },
                { label = 'Author', value = tostring(row.author_name or row.author_citizenid or 'Unknown') },
                { label = 'Created', value = when(row.created_at, '—') },
            } },
        } }
    end

    local function showReport(row)
        local content = reportContent(row)
        if not resultView.tabs then
            resultView.tabs = { { id = 'record', label = 'Record', content = resultView.content } }
            resultView.content = nil
        end
        local reportTab
        for _, tab in ipairs(resultView.tabs) do
            if tab.id == 'record-report' then reportTab = tab; break end
        end
        if reportTab then
            reportTab.content = content
        else
            resultView.tabs[#resultView.tabs + 1] = { id = 'record-report', label = 'Record Report', content = content }
        end
        return update('results', nil, nil, 'record-report')
    end

    local function personContent(record)
        local activity = {}
        for _, row in ipairs(record.warrants or {}) do activity[#activity + 1] = {
            id = 'warrant-' .. row.id, title = 'Active warrant #' .. row.id, description = row.reason,
            timestamp = when(row.expires_at, ''), icon = 'gavel', tone = 'destructive',
        } end
        for _, row in ipairs(record.bolos or {}) do activity[#activity + 1] = {
            id = 'bolo-' .. row.id, title = 'Active BOLO: ' .. row.title, description = row.description,
            timestamp = when(row.expires_at, ''), icon = 'siren', tone = 'warning',
        } end
        for _, row in ipairs(record.reports or {}) do activity[#activity + 1] = {
            id = 'report-' .. row.id, title = ('Report #%s · %s'):format(row.id, row.title),
            description = row.status, timestamp = when(row.created_at, ''), icon = 'file-text',
        } end
        for index, row in ipairs(record.firearms or {}) do activity[#activity + 1] = {
            id = 'firearm-' .. index, title = row.weapon_name or 'Registered firearm',
            description = row.serial, timestamp = when(row.purchased_at, ''), icon = 'crosshair', tone = 'primary',
        } end
        for index, row in ipairs(record.criminal or {}) do activity[#activity + 1] = {
            id = 'criminal-' .. index, title = row.charge_code or 'Criminal record',
            description = row.notes, timestamp = when(row.created_at, ''), icon = 'scale', tone = 'warning',
        } end
        for index, row in ipairs(record.medical or {}) do activity[#activity + 1] = {
            id = 'medical-' .. index, title = 'Medical record', description = row.notes,
            timestamp = when(row.created_at, ''), icon = 'heart-pulse', tone = 'success',
        } end
        return {
            title = record.name or record.citizenid, description = 'Citizen profile and linked MDT history',
            blocks = {
                { type = 'details', title = 'Identity', columns = 2, items = {
                    { label = 'Citizen ID', value = record.citizenid, icon = 'contact' },
                    { label = 'Phone', value = record.phone or 'Not recorded', icon = 'phone' },
                    { label = 'Date of birth', value = record.birthdate or 'Not recorded' },
                    { label = 'Nationality', value = record.nationality or 'Not recorded' },
                    { label = 'Occupation', value = record.job or 'Unemployed' },
                    { label = 'Driver licence', value = record.driverLicensed and 'Valid' or 'Not held', tone = record.driverLicensed and 'success' or 'warning' },
                    { label = 'Weapon licence', value = record.weaponLicence or 'Not held', icon = 'shield' },
                } },
                { type = 'timeline', title = 'Linked records and alerts', items = activity, empty = 'No linked records.' },
            },
        }
    end

    local function openPerson(citizenid)
        local record, err = QB.callback.trigger('qbmdt:server:person', citizenid)
        if not record then return message(false, nil, err or 'Citizen not found.') end
        return showResult(personContent(record))
    end

    local function openVehicle(plate)
        local row, err = QB.callback.trigger('qbmdt:server:vehicle', plate)
        if not row then return message(false, nil, err or 'Vehicle not found.') end
        local alerts = {}
        for _, bolo in ipairs(row.bolos or {}) do alerts[#alerts + 1] = {
            id = 'vehicle-bolo-' .. bolo.id, title = bolo.title, description = bolo.description,
            timestamp = when(bolo.expires_at, ''), icon = 'siren', tone = 'destructive',
        } end
        return showResult({ title = row.plate, description = row.model or 'Vehicle registration', blocks = {
            { type = 'details', title = 'Registration', columns = 2, items = {
                { label = 'Plate', value = row.plate, icon = 'car-front' },
                { label = 'Model', value = row.model or 'Unknown' },
                { label = 'Owner', value = row.owner_name or row.citizenid or 'State / unowned', icon = 'contact' },
                { label = 'Citizen ID', value = row.citizenid or '—' },
                { label = 'State', value = row.state or 'unknown', tone = row.state == 'out' and 'warning' or 'neutral' },
                { label = 'Garage / lot', value = row.impound_lot or row.garage_id or '—' },
            } },
            { type = 'timeline', title = 'Active BOLOs', items = alerts, empty = 'No active BOLO for this vehicle.' },
        } })
    end

    local peopleFields = { { id = 'query', label = 'Name, citizen ID, or phone', type = 'text', required = true, minLength = 2, maxLength = 64 } }
    local lookupActions = { action('person:search', medicalAccess and not criminalAccess and 'Search patients' or 'Search citizens', 'users', peopleFields) }
    if policeAccess then
        lookupActions[#lookupActions + 1] = action('vehicle:search', 'Search vehicles', 'car-front', {
            { id = 'query', label = 'Plate, model, owner, or citizen ID', type = 'text', required = true, minLength = 2, maxLength = 64 },
        })
        lookupActions[#lookupActions + 1] = action('charges:list', 'Penal code', 'scale')
        lookupActions[#lookupActions + 1] = action('firearm:search', 'Firearm registry', 'crosshair', {
            { id = 'serial', label = 'Serial number', type = 'text', required = true, maxLength = 96 },
        })
    end
    navigation[#navigation + 1] = { id = 'search', label = medicalAccess and not criminalAccess and 'Patients' or 'Search', icon = 'search',
        content = { title = 'Records search', description = 'Search broadly, then select a row to open the full record.', blocks = { { type = 'actions', actions = lookupActions } } } }

    if policeAccess then
        table.insert(navigation, 1, { id = 'dashboard', label = 'Dashboard', icon = 'layout-dashboard',
            content = { title = 'Operations dashboard', blocks = { { type = 'empty', title = 'Loading operations', description = 'Fetching current MDT activity.' } } } })
        navigation[#navigation + 1] = { id = 'reports', label = 'Reports', icon = 'file-text', content = {
            title = 'Incident reports', blocks = { { type = 'actions', actions = {
                action('report:create', 'New incident report', 'file-plus', {
                    { id = 'title', label = 'Title', type = 'text', required = true, maxLength = 160 },
                    { id = 'citizenid', label = req('report', 'subject') and 'Subject (citizen ID or name)' or 'Subject (citizen ID or name, optional)',
                        type = 'text', maxLength = 64, required = req('report', 'subject') },
                    { id = 'charge', label = req('report', 'charge') and 'Charge' or 'Charge (optional)', type = 'combobox',
                        required = req('report', 'charge'), options = chargeOptions,
                        placeholder = 'Type to search charges...' },
                    { id = 'narrative', label = 'Incident narrative', type = 'textarea', required = req('report', 'narrative'), maxLength = 8000 },
                }, 'primary'), action('report:refresh', 'Refresh reports', 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'cases', label = 'Cases', icon = 'folder-search', content = {
            title = 'Investigations', description = 'Use Attach report to case to link an incident report to an investigation.', blocks = { { type = 'actions', actions = {
                action('case:create', 'Open a case', 'folder-plus', {
                    { id = 'title', label = 'Case title', type = 'text', required = true, maxLength = 160 },
                    { id = 'priority', label = 'Priority', type = 'select', required = true, default = 'normal', options = {
                        { value = 'low', label = 'Low' }, { value = 'normal', label = 'Normal' },
                        { value = 'high', label = 'High' }, { value = 'critical', label = 'Critical' },
                    } },
                    { id = 'summary', label = 'Investigation summary', type = 'textarea', required = req('case', 'summary'), maxLength = 8000 },
                }, 'primary'), action('case:attach-report', 'Attach report to case', 'plus', {
                    { id = 'case_id', label = 'Case', type = 'select', searchable = true, required = true,
                        options = caseOptions, placeholder = 'Search cases by number or title...' },
                    { id = 'report_id', label = 'Report', type = 'select', searchable = true, required = true,
                        options = reportOptions, placeholder = 'Search reports by title or subject...' },
                }), action('case:refresh', 'Refresh cases', 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'warrants', label = 'Warrants', icon = 'gavel', content = {
            title = 'Warrants', blocks = { { type = 'actions', actions = {
                action('warrant:create', 'Issue warrant', 'file-warning', {
                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true, maxLength = 64 },
                    { id = 'reason', label = 'Probable cause / reason', type = 'textarea', required = req('warrant', 'reason'), maxLength = 1000 },
                    { id = 'days', label = 'Valid for days', type = 'number', required = true, default = C.operations.warrantDefaultDays, min = 1, max = C.operations.warrantMaxDays },
                }, 'primary'), action('warrant:refresh', 'Refresh warrants', 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'bolos', label = 'BOLOs', icon = 'siren', content = {
            title = 'Be On Lookout', blocks = { { type = 'actions', actions = {
                action('bolo:create', 'Create BOLO', 'siren', {
                    { id = 'subject_type', label = 'Subject type', type = 'select', required = true, default = 'person', options = {
                        { value = 'person', label = 'Person' }, { value = 'vehicle', label = 'Vehicle' },
                    } },
                    { id = 'identifier', label = 'Citizen ID, name or plate', type = 'text', required = true, maxLength = 96 },
                    { id = 'title', label = 'Alert title', type = 'text', required = true, maxLength = 160 },
                    { id = 'description', label = 'Description and instructions', type = 'textarea', required = req('bolo', 'description'), maxLength = 1500 },
                    { id = 'days', label = 'Valid for days', type = 'number', required = true, default = C.operations.boloDefaultDays, min = 1, max = C.operations.boloMaxDays },
                }, 'primary'), action('bolo:refresh', 'Refresh BOLOs', 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'tools', label = 'Tools', icon = 'briefcase', content = {
            title = 'Police tools', blocks = { { type = 'actions', actions = {
                action('criminal:create', 'Add criminal record', 'file-plus', {
                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                    { id = 'charge', label = 'Charge', type = 'combobox', required = true, options = chargeOptions,
                        placeholder = 'Type to search charges...' },
                    { id = 'notes', label = 'Notes', type = 'textarea', required = req('criminal', 'notes'), maxLength = 1000 },
                }), action('analysis:start', 'Analyse ballistic casing', 'microscope', {
                    { id = 'caseid', label = 'Casing case ID', type = 'text', required = true },
                }),
            } } } } }
        if policeBoss then
            navigation[#navigation + 1] = { id = 'charges', label = 'Charges', icon = 'scale',
                content = chargeManagementContent(QB.callback.trigger('qbmdt:server:manageCharges') or {}) }
        end
    end

    if medicalAccess then
        navigation[#navigation + 1] = { id = 'medical', label = 'Medical records', icon = 'heart-pulse', content = {
            title = 'Medical records', blocks = { { type = 'actions', actions = {
                action('medical:create', 'Add medical record', 'file-plus', {
                    { id = 'citizenid', label = 'Citizen ID', type = 'text', required = true },
                    { id = 'notes', label = 'Treatment / notes', type = 'textarea', required = req('medical', 'notes'), maxLength = 1000 },
                }),
            } } } } }
    end
    navigation[#navigation + 1] = resultView

    -- A list that cannot load says why (and logs it) instead of showing an empty table.
    local function listFailed(viewId, slot, what, err)
        err = tostring(err or 'no response from the server')
        print(('^1[kora_mdt]^7 could not load %s: %s'):format(what, err))
        local view = findView(viewId)
        local blocks = view and view.content and view.content.blocks
        if blocks and (blocks[slot] == nil or blocks[slot].type == 'empty') then
            blocks[slot] = { type = 'empty', title = ('Could not load %s'):format(what), description = err, icon = 'alert-triangle' }
        end
        return nil, err
    end
    -- Runs every refresher (all of them, even after a failure); returns the first failure reason.
    local function refreshAll(...)
        local failure
        for _, refresh in ipairs({ ... }) do
            local ok, err = refresh()
            if not ok and not failure then failure = err or 'unknown error' end
        end
        return failure
    end
    local function savedNotice(success, failure)
        if failure then
            return { tone = 'warning', message = ('%s The list could not be refreshed: %s'):format(success, failure) }
        end
        return { tone = 'success', message = success }
    end

    local function refreshDashboard()
        local data, dashboardErr = QB.callback.trigger('qbmdt:server:dashboard')
        if not data then return listFailed('dashboard', 1, 'the dashboard', dashboardErr) end
        local recent = {}
        for _, row in ipairs(data.recent or {}) do recent[#recent + 1] = {
            id = tostring(row.id), title = ('Report #%s · %s'):format(row.id, row.title),
            description = row.status, timestamp = when(row.updated_at, ''), icon = 'file-text',
            tone = row.status == 'open' and 'warning' or 'neutral',
        } end
        findView('dashboard').content = { title = 'Operations dashboard', description = 'Current records requiring attention.', blocks = {
            { type = 'stats', items = {
                { label = 'Open reports', value = tonumber(data.open_reports) or 0, icon = 'file-text', tone = 'primary' },
                { label = 'Open cases', value = tonumber(data.open_cases) or 0, icon = 'folder-search' },
                { label = 'Active warrants', value = tonumber(data.active_warrants) or 0, icon = 'gavel', tone = 'warning' },
                { label = 'Active BOLOs', value = tonumber(data.active_bolos) or 0, icon = 'siren', tone = 'destructive' },
            } }, { type = 'timeline', title = 'Recent reports', items = recent, empty = 'No incident reports have been filed.' },
        } }
        return true
    end

    local function refreshReports()
        local rows, err = QB.callback.trigger('qbmdt:server:reports')
        if not rows then return listFailed('reports', 2, 'reports', err) end
        local optionRows = QB.callback.trigger('qbmdt:server:reportOptions')
        if optionRows then
            for index = #reportOptions, 1, -1 do reportOptions[index] = nil end
            for _, row in ipairs(optionRows) do
                reportOptions[#reportOptions + 1] = {
                    value = tostring(row.id), label = ('%s - %s'):format(row.title or 'Untitled', row.subject or 'Unknown'),
                }
            end
        end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = {
            id = tostring(row.id), status = statusCell(row.status), title = row.title,
            subject = row.subject_name or row.subject_citizenid or row.subject_text or 'Unknown', charge = row.charge_label or row.charge_text or '—', updated = when(row.updated_at, '—'),
        } end
        local view = findView('reports')
        view.content.blocks[2] = { type = 'table', id = 'report-list', title = 'Recent reports', searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = 'status', sortable = true },
                { key = 'title', label = 'Title', sortable = true }, { key = 'subject', label = 'Subject', sortable = true },
                { key = 'charge', label = 'Charge' }, { key = 'updated', label = 'Updated', sortable = true } },
            rows = output, empty = 'No reports found.', action = 'report:select', idKey = 'id' }
        return true
    end

    local function refreshCases()
        local rows, err = QB.callback.trigger('qbmdt:server:cases')
        if not rows then return listFailed('cases', 2, 'cases', err) end
        for index = #caseOptions, 1, -1 do caseOptions[index] = nil end
        local output = {}
        for _, row in ipairs(rows) do
            caseOptions[#caseOptions + 1] = { value = tostring(row.id), label = ('#%s - %s'):format(row.id, row.title or 'Untitled') }
            output[#output + 1] = { id = tostring(row.id), priority = statusCell(row.priority),
                status = statusCell(row.status), title = row.title, lead = row.lead_citizenid, reports = tonumber(row.report_count) or 0, updated = when(row.updated_at, '—') }
        end
        findView('cases').content.blocks[2] = { type = 'table', id = 'case-list', title = 'Investigation files', searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'priority', label = 'Priority', sortable = true },
                { key = 'status', label = 'status', sortable = true }, { key = 'title', label = 'Case', sortable = true },
                { key = 'lead', label = 'Lead' }, { key = 'reports', label = 'Reports', align = 'right' }, { key = 'updated', label = 'Updated' } },
            rows = output, empty = 'No cases found.', action = 'case:select', idKey = 'id' }
        return true
    end

    local function refreshWarrants()
        local rows, err = QB.callback.trigger('qbmdt:server:warrants')
        if not rows then return listFailed('warrants', 2, 'warrants', err) end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = { id = tostring(row.id), status = statusCell(row.status),
            subject = row.subject_name or row.citizenid, citizenid = row.citizenid, reason = row.reason, expires = when(row.expires_at, '—') } end
        findView('warrants').content.blocks[2] = { type = 'table', id = 'warrant-list', title = 'Warrant register', searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = 'status', sortable = true },
                { key = 'subject', label = 'Subject', sortable = true }, { key = 'reason', label = 'Reason' }, { key = 'expires', label = 'Expires', sortable = true } },
            rows = output, empty = 'No warrants found.', action = 'warrant:select', idKey = 'id' }
        return true
    end

    local function refreshBolos()
        local rows, err = QB.callback.trigger('qbmdt:server:bolos')
        if not rows then return listFailed('bolos', 2, 'BOLOs', err) end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = { id = tostring(row.id), status = statusCell(row.status),
            kind = tostring(row.subject_type or ''), subject = tostring(row.subject_label or row.subject_identifier or ''), title = tostring(row.title or ''),
            description = tostring(row.description or ''), expires = when(row.expires_at, '—') } end
        findView('bolos').content.blocks[2] = { type = 'table', id = 'bolo-list', title = 'Current and recent BOLOs', searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = 'status', sortable = true },
                { key = 'kind', label = 'Type', sortable = true }, { key = 'subject', label = 'Subject', sortable = true },
                { key = 'title', label = 'Alert' }, { key = 'expires', label = 'Expires' } },
            rows = output, empty = 'No BOLOs found.', action = 'bolo:select', idKey = 'id' }
        return true
    end

    if policeAccess then
        refreshAll(refreshDashboard, refreshReports, refreshCases, refreshWarrants, refreshBolos)
    end

    Kora.nui.registerApp({
        id = 'qbmdt:terminal', title = role == 'medical' and 'Medical Records Terminal' or 'Mobile Data Terminal',
        description = role == 'medical' and 'Patient and treatment records' or 'Law enforcement operations and records',
        icon = role == 'medical' and 'heart-pulse' or 'monitor-smartphone', width = 1240, height = 820,
        navigation = navigation, footer = 'Every record is permission-checked by the server. Operational changes are audited.',
        onAction = function(selectedId, context)
            local input = type(context and context.value) == 'table' and context.value or {}
            local itemId = context and context.itemId

            if selectedId == 'person:search' then
                local rows, err = QB.callback.trigger('qbmdt:server:searchPeople', input.query)
                if not rows then return message(false, nil, err) end
                return update('search', { title = 'Citizen search', description = ('Results for “%s”'):format(input.query), blocks = {
                    { type = 'actions', actions = lookupActions },
                    { type = 'table', id = 'people-results', searchable = true, pageSize = 12,
                        columns = { { key = 'citizenid', label = 'Citizen ID', sortable = true }, { key = 'name', label = 'Name', sortable = true },
                            { key = 'phone_number', label = 'Phone' }, { key = 'last_updated', label = 'Last seen', sortable = true } },
                        rows = rows, empty = 'No citizens matched.', action = 'person:select', idKey = 'citizenid' },
                } })
            elseif selectedId == 'person:select' and itemId then
                return openPerson(itemId)
            elseif selectedId == 'vehicle:search' and policeAccess then
                local rows, err = QB.callback.trigger('qbmdt:server:searchVehicles', input.query)
                if not rows then return message(false, nil, err) end
                return update('search', { title = 'Vehicle search', description = ('Results for “%s”'):format(input.query), blocks = {
                    { type = 'actions', actions = lookupActions },
                    { type = 'table', id = 'vehicle-results', searchable = true, pageSize = 12,
                        columns = { { key = 'plate', label = 'Plate', sortable = true }, { key = 'model', label = 'Model', sortable = true },
                            { key = 'owner_name', label = 'Owner', sortable = true }, { key = 'citizenid', label = 'Citizen ID' }, { key = 'state', label = 'State', sortable = true } },
                        rows = rows, empty = 'No vehicles matched.', action = 'vehicle:select', idKey = 'plate' },
                } })
            elseif selectedId == 'vehicle:select' and itemId and policeAccess then
                return openVehicle(itemId)
            elseif selectedId == 'charges:list' and policeAccess then
                local rows, err = QB.callback.trigger('qbmdt:server:charges')
                if not rows then return message(false, nil, err) end
                return showResult({ title = 'Penal code', description = 'Server-authorized charge catalogue.', blocks = { {
                    type = 'table', id = 'charges', searchable = true, pageSize = 12,
                    columns = { { key = 'code', label = 'Code', sortable = true }, { key = 'label', label = 'Charge', sortable = true },
                        { key = 'fine', label = 'Fine', align = 'right', sortable = true } }, rows = rows, empty = 'No charges configured.',
                } } })
            elseif selectedId == 'charge:refresh' and policeBoss then
                local rows, err = QB.callback.trigger('qbmdt:server:manageCharges')
                if not rows then return message(false, nil, err) end
                return update('charges', chargeManagementContent(rows))
            elseif selectedId == 'charge:create' and policeBoss then
                local ok, err = QB.callback.trigger('qbmdt:server:createCharge', input)
                if not ok then return message(false, nil, err) end
                setChargeOptions(QB.callback.trigger('qbmdt:server:charges') or {})
                local managed = QB.callback.trigger('qbmdt:server:manageCharges') or {}
                return update('charges', chargeManagementContent(managed), { tone = 'success', message = 'Charge created.' })
            elseif selectedId == 'charge:select' and policeBoss and itemId then
                local rows = QB.callback.trigger('qbmdt:server:manageCharges') or {}
                for _, charge in ipairs(rows) do
                    if tostring(charge.code) == tostring(itemId) then selectedCharge = charge; break end
                end
                if not selectedCharge then return message(false, nil, 'Charge not found.') end
                return showResult(chargeContent(selectedCharge))
            elseif selectedId == 'charge:edit' and policeBoss and selectedCharge then
                local ok, err = QB.callback.trigger('qbmdt:server:updateCharge', selectedCharge.code, input.label, input.fine)
                if not ok then return message(false, nil, err) end
                setChargeOptions(QB.callback.trigger('qbmdt:server:charges') or {})
                for _, charge in ipairs(QB.callback.trigger('qbmdt:server:manageCharges') or {}) do
                    if tostring(charge.code) == tostring(selectedCharge.code) then selectedCharge = charge; break end
                end
                return showResult(chargeContent(selectedCharge), { tone = 'success', message = 'Charge updated.' })
            elseif selectedId == 'firearm:search' and policeAccess then
                local row, err = QB.callback.trigger('qbmdt:server:shopFirearm', input.serial)
                if not row then return message(false, nil, err or 'No registered firearm found.') end
                return showResult({ title = row.weapon_name or input.serial, description = 'Firearm registration', blocks = { {
                    type = 'details', columns = 2, items = { { label = 'Serial', value = row.serial or input.serial },
                        { label = 'Owner citizen ID', value = row.owner_citizenid }, { label = 'Licence', value = row.licence_number or '—' },
                        { label = 'Purchased', value = when(row.purchased_at, '—') } },
                } } })
            elseif selectedId == 'report:refresh' and policeAccess then
                local failure = refreshAll(refreshReports, refreshDashboard)
                if failure then return message(false, nil, 'Could not refresh reports: ' .. failure) end
                return update('reports', nil, { tone = 'success', message = 'Reports refreshed.' })
            elseif selectedId == 'report:create' and policeAccess then
                local id, err = QB.callback.trigger('qbmdt:server:createReport', input)
                if not id then return message(false, nil, err) end
                local failure = refreshAll(refreshReports, refreshDashboard)
                return update('reports', nil, savedNotice(('Incident report #%s created.'):format(id), failure))
            elseif (selectedId == 'report:select' or selectedId == 'report:open-linked') and itemId and policeAccess then
                local row, err = QB.callback.trigger('qbmdt:server:report', itemId)
                if not row then return message(false, nil, err or 'Report not found.') end
                selectedReport = row
                return showReport(row)
            elseif selectedId == 'report:close' and selectedReport and policeAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:closeReport', selectedReport.id)
                if not ok then return message(false, nil, err) end
                selectedReport.status = 'closed'
                return update('reports', nil, savedNotice('Report closed.', refreshAll(refreshReports, refreshDashboard)))
            elseif selectedId == 'case:refresh' and policeAccess then
                local failure = refreshAll(refreshCases, refreshDashboard)
                if failure then return message(false, nil, 'Could not refresh cases: ' .. failure) end
                return update('cases', nil, { tone = 'success', message = 'Cases refreshed.' })
            elseif selectedId == 'case:attach-report' and policeAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:linkCaseReport', input.case_id, input.report_id)
                if not ok then return message(false, nil, err) end
                return update('cases', nil, savedNotice('Report attached to case.', refreshAll(refreshCases)))
            elseif selectedId == 'case:create' and policeAccess then
                local id, err = QB.callback.trigger('qbmdt:server:createCase', input)
                if not id then return message(false, nil, err) end
                local failure = refreshAll(refreshCases, refreshDashboard)
                local row = QB.callback.trigger('qbmdt:server:case', id)
                if row then selectedCase = row; return showResult(caseContent(row), savedNotice(('Case #%s opened. Add reports with + Add report.'):format(id), failure)) end
                return update('cases', nil, savedNotice(('Case #%s opened.'):format(id), failure))
            elseif selectedId == 'case:select' and itemId and policeAccess then
                local row, err = QB.callback.trigger('qbmdt:server:case', itemId)
                if not row then return message(false, nil, err or 'Case not found.') end
                selectedCase = row
                return showResult(caseContent(row))
            elseif selectedId == 'case:link-report' and selectedCase and policeAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:linkCaseReport', selectedCase.id, input.report_id)
                if ok then
                    local failure = refreshAll(refreshCases)
                    local row = QB.callback.trigger('qbmdt:server:case', selectedCase.id)
                    if row then selectedCase = row; return showResult(caseContent(row), savedNotice('Report added. Use + Add report to attach another.', failure)) end
                    return update('cases', nil, savedNotice('Report linked to case.', failure))
                end
                return message(false, nil, err)
            elseif (selectedId == 'case:investigate' or selectedId == 'case:close' or selectedId == 'case:reopen') and selectedCase and policeAccess then
                local state = selectedId == 'case:investigate' and 'investigating' or selectedId == 'case:close' and 'closed' or 'open'
                local ok, err = QB.callback.trigger('qbmdt:server:updateCaseStatus', selectedCase.id, state)
                if not ok then return message(false, nil, err) end
                selectedCase.status = state
                return update('cases', nil, savedNotice('Case marked ' .. state .. '.', refreshAll(refreshCases, refreshDashboard)))
            elseif selectedId == 'warrant:refresh' and policeAccess then
                local failure = refreshAll(refreshWarrants, refreshDashboard)
                if failure then return message(false, nil, 'Could not refresh warrants: ' .. failure) end
                return update('warrants', nil, { tone = 'success', message = 'Warrants refreshed.' })
            elseif selectedId == 'warrant:create' and policeAccess then
                local id, err = QB.callback.trigger('qbmdt:server:createWarrant', input)
                if not id then return message(false, nil, err) end
                return update('warrants', nil, savedNotice(('Warrant #%s issued.'):format(id), refreshAll(refreshWarrants, refreshDashboard)))
            elseif selectedId == 'warrant:select' and itemId and policeAccess then
                selectedWarrant = nil
                for _, row in ipairs(QB.callback.trigger('qbmdt:server:warrants') or {}) do if tostring(row.id) == tostring(itemId) then selectedWarrant = row; break end end
                if not selectedWarrant then return message(false, nil, 'Warrant not found.') end
                local actions = {}
                if selectedWarrant.status == 'active' then actions = {
                    { id = 'warrant:serve', label = 'Mark served', icon = 'check-circle', variant = 'primary', confirm = 'Mark this warrant as served?' },
                    { id = 'warrant:revoke', label = 'Revoke warrant', icon = 'x-circle', variant = 'destructive', confirm = 'Revoke this warrant?' },
                } end
                return showResult({ title = ('Warrant #%s'):format(tostring(selectedWarrant.id)), description = tostring(selectedWarrant.reason or ''), actions = actions, blocks = { {
                    type = 'details', columns = 2, items = { { label = 'status', value = tostring(selectedWarrant.status or 'unknown') },
                        { label = 'Subject', value = tostring(selectedWarrant.subject_name or selectedWarrant.citizenid or 'Unknown') },
                        { label = 'Citizen ID', value = tostring(selectedWarrant.citizenid or '—') }, { label = 'Expires', value = when(selectedWarrant.expires_at, '—') },
                        { label = 'Issued by', value = tostring(selectedWarrant.author_citizenid or 'Unknown') }, },
                } } })
            elseif (selectedId == 'warrant:serve' or selectedId == 'warrant:revoke') and selectedWarrant and policeAccess then
                local state = selectedId == 'warrant:serve' and 'served' or 'revoked'
                local ok, err = QB.callback.trigger('qbmdt:server:closeWarrant', selectedWarrant.id, state)
                if not ok then return message(false, nil, err) end
                selectedWarrant.status = state
                return update('warrants', nil, savedNotice('Warrant marked ' .. state .. '.', refreshAll(refreshWarrants, refreshDashboard)))
            elseif selectedId == 'bolo:refresh' and policeAccess then
                local failure = refreshAll(refreshBolos, refreshDashboard)
                if failure then return message(false, nil, 'Could not refresh BOLOs: ' .. failure) end
                return update('bolos', nil, { tone = 'success', message = 'BOLOs refreshed.' })
            elseif selectedId == 'bolo:create' and policeAccess then
                local id, err = QB.callback.trigger('qbmdt:server:createBolo', input)
                if not id then return message(false, nil, err or 'The BOLO could not be created. Check every field and try again.') end
                return update('bolos', nil, savedNotice(('BOLO #%s created.'):format(id), refreshAll(refreshBolos, refreshDashboard)))
            elseif selectedId == 'bolo:select' and itemId and policeAccess then
                selectedBolo = nil
                for _, row in ipairs(QB.callback.trigger('qbmdt:server:bolos') or {}) do if tostring(row.id) == tostring(itemId) then selectedBolo = row; break end end
                if not selectedBolo then return message(false, nil, 'BOLO not found.') end
                local actions = selectedBolo.status == 'active' and { { id = 'bolo:resolve', label = 'Resolve BOLO', icon = 'check-circle', variant = 'primary', confirm = 'Resolve this BOLO?' } } or {}
                local details = { { label = 'status', value = tostring(selectedBolo.status or 'unknown') },
                    { label = 'Type', value = tostring(selectedBolo.subject_type or '—') }, { label = 'Subject', value = tostring(selectedBolo.subject_label or selectedBolo.subject_identifier or '—') },
                    { label = 'Expires', value = when(selectedBolo.expires_at, '—') }, { label = 'Created by', value = tostring(selectedBolo.author_citizenid or 'Unknown') }, }
                if (C.bolo or {}).showLinkedCitizen ~= false and selectedBolo.subject_type == 'person' and selectedBolo.linked_citizenid then
                    table.insert(details, 4, { label = 'Linked citizen ID', value = tostring(selectedBolo.linked_citizenid) })
                end
                return showResult({ title = ('BOLO #%s · %s'):format(tostring(selectedBolo.id), tostring(selectedBolo.title or 'Untitled')),
                    description = tostring(selectedBolo.description or ''), actions = actions, blocks = { {
                    type = 'details', columns = 2, items = details,
                } } })
            elseif selectedId == 'bolo:resolve' and selectedBolo and policeAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:resolveBolo', selectedBolo.id)
                if not ok then return message(false, nil, err) end
                selectedBolo.status = 'resolved'
                return update('bolos', nil, savedNotice('BOLO resolved.', refreshAll(refreshBolos, refreshDashboard)))
            elseif selectedId == 'criminal:create' and criminalAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:addCriminal', input.citizenid, input.charge, input.notes)
                return message(ok, 'Criminal record saved.', err)
            elseif selectedId == 'medical:create' and medicalAccess then
                local ok, err = QB.callback.trigger('qbmdt:server:addMedical', input.citizenid, input.notes)
                return message(ok, 'Medical record saved.', err)
            elseif selectedId == 'analysis:start' and criminalAccess then
                QB.events.trigger('qbmdt:server:beginAnalysis', input.caseid)
                return { notice = { tone = 'primary', message = 'Ballistic analysis started.' } }
            end
            return {}
        end,
    })
    Kora.nui.openApp('qbmdt:terminal')
end

RegisterNetEvent('qbmdt:client:open', openTerminal)
