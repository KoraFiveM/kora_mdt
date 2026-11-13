local C = Config.mdt

local function action(id, label, icon, fields, variant)
    return { id = id, label = label, icon = icon, fields = fields, variant = variant }
end

local function message(ok, success, failure)
    return { notice = { tone = ok and 'success' or 'destructive', message = ok and success or (failure or Kora.lang('Error.action_failed')) } }
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
    return { label = tostring(value or Kora.lang('Terminal.unknown')), badge = true, tone = tone }
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
        return { title = Kora.lang('Terminal.charge_management'), description = Kora.lang('Terminal.create_charges_for_the_criminal'), blocks = {
            { type = 'actions', actions = {
                action('charge:create', Kora.lang('Terminal.create_charge'), 'plus', {
                    { id = 'code', label = Kora.lang('Terminal.charge_code'), type = 'text', required = true, maxLength = 32 },
                    { id = 'label', label = Kora.lang('Terminal.charge_name'), type = 'text', required = true, maxLength = 128 },
                    { id = 'fine', label = Kora.lang('Terminal.fine'), type = 'number', required = true, min = 0, max = 2000000000 },
                }, 'primary'), action('charge:refresh', Kora.lang('Terminal.refresh_charges'), 'refresh-cw'),
            } },
            { type = 'table', id = 'managed-charges', searchable = true, pageSize = 12,
                columns = { { key = 'label', label = Kora.lang('Terminal.charge'), sortable = true },
                    { key = 'fine', label = Kora.lang('Terminal.fine'), align = 'right', sortable = true },
                    { key = 'active', label = Kora.lang('Terminal.active'), sortable = true } },
                rows = rows, empty = Kora.lang('Terminal.no_charges_configured'),
                action = 'charge:select', idKey = 'code' },
        } }
    end
    local function chargeContent(charge)
        return {
            title = charge.label,
            description = Kora.lang('Terminal.charge_code_prefix') .. tostring(charge.code),
            actions = { action('charge:edit', Kora.lang('Terminal.edit_charge'), 'pencil', {
                { id = 'label', label = Kora.lang('Terminal.charge_name'), type = 'text', required = true, maxLength = 128, default = charge.label },
                { id = 'fine', label = Kora.lang('Terminal.fine'), type = 'number', required = true, min = 0, max = 2000000000, default = charge.fine },
            }, 'primary') },
            blocks = { { type = 'details', columns = 2, items = {
                { label = Kora.lang('Terminal.code'), value = tostring(charge.code) },
                { label = Kora.lang('Terminal.charge'), value = tostring(charge.label) },
                { label = Kora.lang('Terminal.fine'), value = tostring(charge.fine) },
                { label = Kora.lang('Terminal.active'), value = tostring(charge.active == true or charge.active == 1) },
            } } },
        }
    end
    if policeAccess then
        setChargeOptions(Kora.callback.trigger('kora_mdt:server:charges') or {})
        local reports = Kora.callback.trigger('kora_mdt:server:reportOptions') or {}
        for _, report in ipairs(reports) do
            reportOptions[#reportOptions + 1] = {
                value = tostring(report.id),
                label = Kora.lang('Terminal.report_option', report.title or Kora.lang('Terminal.untitled'), report.subject or Kora.lang('Terminal.unknown')),
            }
        end
        local cases = Kora.callback.trigger('kora_mdt:server:cases') or {}
        for _, case in ipairs(cases) do
            caseOptions[#caseOptions + 1] = {
                value = tostring(case.id),
                label = Kora.lang('Terminal.case_option', case.id, case.title or Kora.lang('Terminal.untitled')),
            }
        end
    end
    local navigation = {}
    local selectedReport, selectedCase, selectedWarrant, selectedBolo

    local resultView = {
        id = 'results', label = Kora.lang('Terminal.record'), icon = 'file-search',
        content = { title = Kora.lang('Terminal.record_viewer'), blocks = { { type = 'empty', title = Kora.lang('Terminal.no_record_selected'),
            description = Kora.lang('Terminal.search_for_a_person_vehicle'), icon = 'search' } } },
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
            id = 'case:link-report', label = Kora.lang('Terminal.add_report'), icon = 'plus', fields = {
                { id = 'report_id', label = Kora.lang('Terminal.search_reports'), type = 'select', searchable = true, required = true,
                    options = reportOptions, placeholder = Kora.lang('Terminal.search_by_title_or_subject') },
            },
        } }
        if row.status == 'open' then
            caseActions[#caseActions + 1] = { id = 'case:investigate', label = Kora.lang('Terminal.begin_investigation'), icon = 'search', variant = 'primary' }
        end
        if row.status ~= 'closed' then
            caseActions[#caseActions + 1] = { id = 'case:close', label = Kora.lang('Terminal.close_case'), icon = 'check-circle', variant = 'primary', confirm = Kora.lang('Terminal.close_this_investigation') }
        else
            caseActions[#caseActions + 1] = { id = 'case:reopen', label = Kora.lang('Terminal.reopen_case'), icon = 'rotate-ccw', confirm = Kora.lang('Terminal.reopen_this_investigation') }
        end
        local linked = {}
        for _, report in ipairs(row.reports or {}) do linked[#linked + 1] = {
            id = tostring(report.id), title = Kora.lang('Terminal.report_summary', tostring(report.id), tostring(report.title or Kora.lang('Terminal.untitled'))),
            description = tostring(report.subject_citizenid or report.subject_text or Kora.lang('Terminal.unknown')), timestamp = when(report.updated_at, ''),
            icon = 'file-text', tone = tostring(report.status) == 'open' and 'warning' or 'neutral',
            actions = { { id = 'report:open-linked', label = Kora.lang('Terminal.open_report'), icon = 'file-search' } },
        } end
        return { title = Kora.lang('Terminal.case_summary', row.id, row.title), description = tostring(row.summary or ''),
            actions = caseActions, blocks = {
                { type = 'details', title = Kora.lang('Terminal.investigation'), columns = 2, items = {
                    { label = Kora.lang('Terminal.status'), value = tostring(row.status or Kora.lang('Terminal.unknown')) }, { label = Kora.lang('Terminal.priority'), value = tostring(row.priority or 'normal') },
                    { label = Kora.lang('Terminal.lead'), value = tostring(row.lead_name or row.lead_citizenid or Kora.lang('Terminal.unknown')) }, { label = Kora.lang('Terminal.opened'), value = when(row.created_at, '—') },
                } }, { type = 'timeline', title = Kora.lang('Terminal.linked_reports'), items = linked, empty = Kora.lang('Terminal.no_reports_linked_to_this') },
            } }
    end

    local function reportContent(row)
        local actions = {}
        if row.status == 'open' then actions[1] = { id = 'report:close', label = Kora.lang('Terminal.close_report'), icon = 'check-circle', variant = 'primary', confirm = Kora.lang('Terminal.close_this_incident_report') } end
        return { title = Kora.lang('Terminal.report_summary', row.id, tostring(row.title or Kora.lang('Terminal.untitled'))),
            description = tostring(row.narrative or ''), actions = actions, blocks = {
            { type = 'details', title = Kora.lang('Terminal.report_details'), columns = 2, items = {
                { label = Kora.lang('Terminal.status'), value = tostring(row.status or Kora.lang('Terminal.unknown')) },
                { label = Kora.lang('Terminal.subject'), value = tostring(row.subject_name or row.subject_citizenid or row.subject_text or Kora.lang('Terminal.unknown')) },
                { label = Kora.lang('Terminal.charge'), value = tostring(row.charge_label or row.charge_text or 'None') },
                { label = Kora.lang('Terminal.fine'), value = tostring(row.fine or '—') },
                { label = Kora.lang('Terminal.author'), value = tostring(row.author_name or row.author_citizenid or Kora.lang('Terminal.unknown')) },
                { label = Kora.lang('Terminal.created'), value = when(row.created_at, '—') },
            } },
        } }
    end

    local function showReport(row)
        local content = reportContent(row)
        if not resultView.tabs then
            resultView.tabs = { { id = 'record', label = Kora.lang('Terminal.record'), content = resultView.content } }
            resultView.content = nil
        end
        local reportTab
        for _, tab in ipairs(resultView.tabs) do
            if tab.id == 'record-report' then reportTab = tab; break end
        end
        if reportTab then
            reportTab.content = content
        else
            resultView.tabs[#resultView.tabs + 1] = { id = 'record-report', label = Kora.lang('Terminal.record_report'), content = content }
        end
        return update('results', nil, nil, 'record-report')
    end

    local function personContent(record)
        local activity = {}
        for _, row in ipairs(record.warrants or {}) do activity[#activity + 1] = {
            id = 'warrant-' .. row.id, title = Kora.lang('Terminal.active_warrant') .. row.id, description = row.reason,
            timestamp = when(row.expires_at, ''), icon = 'gavel', tone = 'destructive',
        } end
        for _, row in ipairs(record.bolos or {}) do activity[#activity + 1] = {
            id = 'bolo-' .. row.id, title = Kora.lang('Terminal.active_bolo') .. row.title, description = row.description,
            timestamp = when(row.expires_at, ''), icon = 'siren', tone = 'warning',
        } end
        for _, row in ipairs(record.reports or {}) do activity[#activity + 1] = {
            id = 'report-' .. row.id, title = Kora.lang('Terminal.report_summary', row.id, row.title),
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
            id = 'medical-' .. index, title = Kora.lang('Terminal.medical_record'), description = row.notes,
            timestamp = when(row.created_at, ''), icon = 'heart-pulse', tone = 'success',
        } end
        return {
            title = record.name or record.citizenid, description = Kora.lang('Terminal.citizen_profile_and_linked_mdt'),
            blocks = {
                { type = 'details', title = Kora.lang('Terminal.identity'), columns = 2, items = {
                    { label = Kora.lang('Terminal.citizen_id'), value = record.citizenid, icon = 'contact' },
                    { label = Kora.lang('Terminal.phone'), value = record.phone or 'Not recorded', icon = 'phone' },
                    { label = Kora.lang('Terminal.date_of_birth'), value = record.birthdate or 'Not recorded' },
                    { label = Kora.lang('Terminal.nationality'), value = record.nationality or 'Not recorded' },
                    { label = Kora.lang('Terminal.occupation'), value = record.job or 'Unemployed' },
                    { label = Kora.lang('Terminal.driver_licence'), value = record.driverLicensed and 'Valid' or 'Not held', tone = record.driverLicensed and 'success' or 'warning' },
                    { label = Kora.lang('Terminal.weapon_licence'), value = record.weaponLicence or 'Not held', icon = 'shield' },
                } },
                { type = 'timeline', title = Kora.lang('Terminal.linked_records_and_alerts'), items = activity, empty = Kora.lang('Terminal.no_linked_records') },
            },
        }
    end

    local function openPerson(citizenid)
        local record, err = Kora.callback.trigger('kora_mdt:server:person', citizenid)
        if not record then return message(false, nil, err or Kora.lang('Error.citizen_not_found')) end
        return showResult(personContent(record))
    end

    local function openVehicle(plate)
        local row, err = Kora.callback.trigger('kora_mdt:server:vehicle', plate)
        if not row then return message(false, nil, err or Kora.lang('Error.vehicle_not_found')) end
        local alerts = {}
        for _, bolo in ipairs(row.bolos or {}) do alerts[#alerts + 1] = {
            id = 'vehicle-bolo-' .. bolo.id, title = bolo.title, description = bolo.description,
            timestamp = when(bolo.expires_at, ''), icon = 'siren', tone = 'destructive',
        } end
        return showResult({ title = row.plate, description = row.model or 'Vehicle registration', blocks = {
            { type = 'details', title = Kora.lang('Terminal.registration'), columns = 2, items = {
                { label = Kora.lang('Terminal.plate'), value = row.plate, icon = 'car-front' },
                { label = Kora.lang('Terminal.model'), value = row.model or Kora.lang('Terminal.unknown') },
                { label = Kora.lang('Terminal.owner'), value = row.owner_name or row.citizenid or 'State / unowned', icon = 'contact' },
                { label = Kora.lang('Terminal.citizen_id'), value = row.citizenid or '—' },
                { label = Kora.lang('Terminal.state'), value = row.state or Kora.lang('Terminal.unknown'), tone = row.state == 'out' and 'warning' or 'neutral' },
                { label = Kora.lang('Terminal.garage_lot'), value = row.impound_lot or row.garage_id or '—' },
            } },
            { type = 'timeline', title = Kora.lang('Terminal.active_bolos'), items = alerts, empty = Kora.lang('Terminal.no_active_bolo_for_this') },
        } })
    end

    local peopleFields = { { id = 'query', label = Kora.lang('Terminal.name_citizen_id_or_phone'), type = 'text', required = true, minLength = 2, maxLength = 64 } }
    local lookupActions = { action('person:search', medicalAccess and not criminalAccess and 'Search patients' or 'Search citizens', 'users', peopleFields) }
    if policeAccess then
        lookupActions[#lookupActions + 1] = action('vehicle:search', Kora.lang('Terminal.search_vehicles'), 'car-front', {
            { id = 'query', label = Kora.lang('Terminal.plate_model_owner_or_citizen'), type = 'text', required = true, minLength = 2, maxLength = 64 },
        })
        lookupActions[#lookupActions + 1] = action('charges:list', Kora.lang('Terminal.penal_code_action'), 'scale')
        lookupActions[#lookupActions + 1] = action('firearm:search', Kora.lang('Terminal.firearm_registry'), 'crosshair', {
            { id = 'serial', label = Kora.lang('Terminal.serial_number'), type = 'text', required = true, maxLength = 96 },
        })
    end
    navigation[#navigation + 1] = { id = 'search', label = medicalAccess and not criminalAccess and 'Patients' or 'Search', icon = 'search',
        content = { title = Kora.lang('Terminal.records_search'), description = Kora.lang('Terminal.search_broadly_then_select_a'), blocks = { { type = 'actions', actions = lookupActions } } } }

    if policeAccess then
        table.insert(navigation, 1, { id = 'dashboard', label = Kora.lang('Terminal.dashboard'), icon = 'layout-dashboard',
            content = { title = Kora.lang('Terminal.operations_dashboard'), blocks = { { type = 'empty', title = Kora.lang('Terminal.loading_operations'), description = Kora.lang('Terminal.fetching_current_mdt_activity') } } } })
        navigation[#navigation + 1] = { id = 'reports', label = Kora.lang('Terminal.reports'), icon = 'file-text', content = {
            title = Kora.lang('Terminal.incident_reports'), blocks = { { type = 'actions', actions = {
                action('report:create', Kora.lang('Terminal.new_incident_report'), 'file-plus', {
                    { id = 'title', label = Kora.lang('Terminal.title'), type = 'text', required = true, maxLength = 160 },
                    { id = 'citizenid', label = req('report', 'subject') and 'Subject (citizen ID or name)' or 'Subject (citizen ID or name, optional)',
                        type = 'text', maxLength = 64, required = req('report', 'subject') },
                    { id = 'charge', label = req('report', 'charge') and 'Charge' or 'Charge (optional)', type = 'combobox',
                        required = req('report', 'charge'), options = chargeOptions,
                        placeholder = Kora.lang('Terminal.type_to_search_charges') },
                    { id = 'narrative', label = Kora.lang('Terminal.incident_narrative'), type = 'textarea', required = req('report', 'narrative'), maxLength = 8000 },
                }, 'primary'), action('report:refresh', Kora.lang('Terminal.refresh_reports'), 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'cases', label = Kora.lang('Terminal.cases'), icon = 'folder-search', content = {
            title = Kora.lang('Terminal.investigations'), description = Kora.lang('Terminal.use_attach_report_to_case'), blocks = { { type = 'actions', actions = {
                action('case:create', Kora.lang('Terminal.open_case'), 'folder-plus', {
                    { id = 'title', label = Kora.lang('Terminal.case_title'), type = 'text', required = true, maxLength = 160 },
                    { id = 'priority', label = Kora.lang('Terminal.priority'), type = 'select', required = true, default = 'normal', options = {
                        { value = 'low', label = Kora.lang('Terminal.low') }, { value = 'normal', label = Kora.lang('Terminal.normal') },
                        { value = 'high', label = Kora.lang('Terminal.high') }, { value = 'critical', label = Kora.lang('Terminal.critical') },
                    } },
                    { id = 'summary', label = Kora.lang('Terminal.investigation_summary'), type = 'textarea', required = req('case', 'summary'), maxLength = 8000 },
                }, 'primary'), action('case:attach-report', Kora.lang('Terminal.attach_report_to_case'), 'plus', {
                    { id = 'case_id', label = Kora.lang('Terminal.case'), type = 'select', searchable = true, required = true,
                        options = caseOptions, placeholder = Kora.lang('Terminal.search_cases_by_number_or') },
                    { id = 'report_id', label = Kora.lang('Terminal.report'), type = 'select', searchable = true, required = true,
                        options = reportOptions, placeholder = Kora.lang('Terminal.search_reports_by_title_or') },
                }), action('case:refresh', Kora.lang('Terminal.refresh_cases'), 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'warrants', label = Kora.lang('Terminal.warrants'), icon = 'gavel', content = {
            title = Kora.lang('Terminal.warrants'), blocks = { { type = 'actions', actions = {
                action('warrant:create', Kora.lang('Terminal.issue_warrant'), 'file-warning', {
                    { id = 'citizenid', label = Kora.lang('Terminal.citizen_id'), type = 'text', required = true, maxLength = 64 },
                    { id = 'reason', label = Kora.lang('Terminal.probable_cause_reason'), type = 'textarea', required = req('warrant', 'reason'), maxLength = 1000 },
                    { id = 'days', label = Kora.lang('Terminal.valid_for_days'), type = 'number', required = true, default = C.operations.warrantDefaultDays, min = 1, max = C.operations.warrantMaxDays },
                }, 'primary'), action('warrant:refresh', Kora.lang('Terminal.refresh_warrants'), 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'bolos', label = Kora.lang('Terminal.bolos'), icon = 'siren', content = {
            title = Kora.lang('Terminal.be_on_lookout'), blocks = { { type = 'actions', actions = {
                action('bolo:create', Kora.lang('Terminal.create_bolo'), 'siren', {
                    { id = 'subject_type', label = Kora.lang('Terminal.subject_type'), type = 'select', required = true, default = 'person', options = {
                        { value = 'person', label = Kora.lang('Terminal.person') }, { value = 'vehicle', label = Kora.lang('Terminal.vehicle') },
                    } },
                    { id = 'identifier', label = Kora.lang('Terminal.citizen_id_name_or_plate'), type = 'text', required = true, maxLength = 96 },
                    { id = 'title', label = Kora.lang('Terminal.alert_title'), type = 'text', required = true, maxLength = 160 },
                    { id = 'description', label = Kora.lang('Terminal.description_and_instructions'), type = 'textarea', required = req('bolo', 'description'), maxLength = 1500 },
                    { id = 'days', label = Kora.lang('Terminal.valid_for_days'), type = 'number', required = true, default = C.operations.boloDefaultDays, min = 1, max = C.operations.boloMaxDays },
                }, 'primary'), action('bolo:refresh', Kora.lang('Terminal.refresh_bolos'), 'refresh-cw'),
            } } } } }
        navigation[#navigation + 1] = { id = 'tools', label = Kora.lang('Terminal.tools'), icon = 'briefcase', content = {
            title = Kora.lang('Terminal.police_tools'), blocks = { { type = 'actions', actions = {
                action('criminal:create', Kora.lang('Terminal.add_criminal_record'), 'file-plus', {
                    { id = 'citizenid', label = Kora.lang('Terminal.citizen_id'), type = 'text', required = true },
                    { id = 'charge', label = Kora.lang('Terminal.charge'), type = 'combobox', required = true, options = chargeOptions,
                        placeholder = Kora.lang('Terminal.type_to_search_charges') },
                    { id = 'notes', label = Kora.lang('Terminal.notes'), type = 'textarea', required = req('criminal', 'notes'), maxLength = 1000 },
                }), action('analysis:start', Kora.lang('Terminal.analyse_ballistic_casing'), 'microscope', {
                    { id = 'caseid', label = Kora.lang('Terminal.casing_case_id'), type = 'text', required = true },
                }),
            } } } } }
        if policeBoss then
            navigation[#navigation + 1] = { id = 'charges', label = Kora.lang('Terminal.charges'), icon = 'scale',
                content = chargeManagementContent(Kora.callback.trigger('kora_mdt:server:manageCharges') or {}) }
        end
    end

    if medicalAccess then
        navigation[#navigation + 1] = { id = 'medical', label = Kora.lang('Terminal.medical_records'), icon = 'heart-pulse', content = {
            title = Kora.lang('Terminal.medical_records'), blocks = { { type = 'actions', actions = {
                action('medical:create', Kora.lang('Terminal.add_medical_record'), 'file-plus', {
                    { id = 'citizenid', label = Kora.lang('Terminal.citizen_id'), type = 'text', required = true },
                    { id = 'notes', label = Kora.lang('Terminal.treatment_notes'), type = 'textarea', required = req('medical', 'notes'), maxLength = 1000 },
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
            blocks[slot] = { type = 'empty', title = Kora.lang('Terminal.could_not_load', what), description = err, icon = 'alert-triangle' }
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
            return { tone = 'warning', message = Kora.lang('Notify.the_list_could_not_be', success, failure) }
        end
        return { tone = 'success', message = success }
    end

    local function refreshDashboard()
        local data, dashboardErr = Kora.callback.trigger('kora_mdt:server:dashboard')
        if not data then return listFailed('dashboard', 1, 'the dashboard', dashboardErr) end
        local recent = {}
        for _, row in ipairs(data.recent or {}) do recent[#recent + 1] = {
            id = tostring(row.id), title = Kora.lang('Terminal.report_summary', row.id, row.title),
            description = row.status, timestamp = when(row.updated_at, ''), icon = 'file-text',
            tone = row.status == 'open' and 'warning' or 'neutral',
        } end
        findView('dashboard').content = { title = Kora.lang('Terminal.operations_dashboard'), description = Kora.lang('Terminal.current_records_requiring_attention'), blocks = {
            { type = 'stats', items = {
                { label = Kora.lang('Terminal.open_reports'), value = tonumber(data.open_reports) or 0, icon = 'file-text', tone = 'primary' },
                { label = Kora.lang('Terminal.open_cases'), value = tonumber(data.open_cases) or 0, icon = 'folder-search' },
                { label = Kora.lang('Terminal.active_warrants'), value = tonumber(data.active_warrants) or 0, icon = 'gavel', tone = 'warning' },
                { label = Kora.lang('Terminal.active_bolos'), value = tonumber(data.active_bolos) or 0, icon = 'siren', tone = 'destructive' },
            } }, { type = 'timeline', title = Kora.lang('Terminal.recent_reports'), items = recent, empty = Kora.lang('Terminal.no_incident_reports_have_been') },
        } }
        return true
    end

    local function refreshReports()
        local rows, err = Kora.callback.trigger('kora_mdt:server:reports')
        if not rows then return listFailed('reports', 2, 'reports', err) end
        local optionRows = Kora.callback.trigger('kora_mdt:server:reportOptions')
        if optionRows then
            for index = #reportOptions, 1, -1 do reportOptions[index] = nil end
            for _, row in ipairs(optionRows) do
                reportOptions[#reportOptions + 1] = {
                    value = tostring(row.id), label = Kora.lang('Terminal.report_option', row.title or Kora.lang('Terminal.untitled'), row.subject or Kora.lang('Terminal.unknown')),
                }
            end
        end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = {
            id = tostring(row.id), status = statusCell(row.status), title = row.title,
            subject = row.subject_name or row.subject_citizenid or row.subject_text or Kora.lang('Terminal.unknown'), charge = row.charge_label or row.charge_text or '—', updated = when(row.updated_at, '—'),
        } end
        local view = findView('reports')
        view.content.blocks[2] = { type = 'table', id = 'report-list', title = Kora.lang('Terminal.recent_reports'), searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = Kora.lang('Terminal.status'), sortable = true },
                { key = 'title', label = Kora.lang('Terminal.title'), sortable = true }, { key = 'subject', label = Kora.lang('Terminal.subject'), sortable = true },
                { key = 'charge', label = Kora.lang('Terminal.charge') }, { key = 'updated', label = Kora.lang('Terminal.updated'), sortable = true } },
            rows = output, empty = Kora.lang('Terminal.no_reports_found'), action = 'report:select', idKey = 'id' }
        return true
    end

    local function refreshCases()
        local rows, err = Kora.callback.trigger('kora_mdt:server:cases')
        if not rows then return listFailed('cases', 2, 'cases', err) end
        for index = #caseOptions, 1, -1 do caseOptions[index] = nil end
        local output = {}
        for _, row in ipairs(rows) do
            caseOptions[#caseOptions + 1] = { value = tostring(row.id), label = Kora.lang('Terminal.case_option', row.id, row.title or Kora.lang('Terminal.untitled')) }
            output[#output + 1] = { id = tostring(row.id), priority = statusCell(row.priority),
                status = statusCell(row.status), title = row.title, lead = row.lead_citizenid, reports = tonumber(row.report_count) or 0, updated = when(row.updated_at, '—') }
        end
        findView('cases').content.blocks[2] = { type = 'table', id = 'case-list', title = Kora.lang('Terminal.investigation_files'), searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'priority', label = Kora.lang('Terminal.priority'), sortable = true },
                { key = 'status', label = Kora.lang('Terminal.status'), sortable = true }, { key = 'title', label = Kora.lang('Terminal.case'), sortable = true },
                { key = 'lead', label = Kora.lang('Terminal.lead') }, { key = 'reports', label = Kora.lang('Terminal.reports'), align = 'right' }, { key = 'updated', label = Kora.lang('Terminal.updated') } },
            rows = output, empty = Kora.lang('Terminal.no_cases_found'), action = 'case:select', idKey = 'id' }
        return true
    end

    local function refreshWarrants()
        local rows, err = Kora.callback.trigger('kora_mdt:server:warrants')
        if not rows then return listFailed('warrants', 2, 'warrants', err) end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = { id = tostring(row.id), status = statusCell(row.status),
            subject = row.subject_name or row.citizenid, citizenid = row.citizenid, reason = row.reason, expires = when(row.expires_at, '—') } end
        findView('warrants').content.blocks[2] = { type = 'table', id = 'warrant-list', title = Kora.lang('Terminal.warrant_register'), searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = Kora.lang('Terminal.status'), sortable = true },
                { key = 'subject', label = Kora.lang('Terminal.subject'), sortable = true }, { key = 'reason', label = Kora.lang('Terminal.reason') }, { key = 'expires', label = Kora.lang('Terminal.expires'), sortable = true } },
            rows = output, empty = Kora.lang('Terminal.no_warrants_found'), action = 'warrant:select', idKey = 'id' }
        return true
    end

    local function refreshBolos()
        local rows, err = Kora.callback.trigger('kora_mdt:server:bolos')
        if not rows then return listFailed('bolos', 2, 'BOLOs', err) end
        local output = {}
        for _, row in ipairs(rows) do output[#output + 1] = { id = tostring(row.id), status = statusCell(row.status),
            kind = tostring(row.subject_type or ''), subject = tostring(row.subject_label or row.subject_identifier or ''), title = tostring(row.title or ''),
            description = tostring(row.description or ''), expires = when(row.expires_at, '—') } end
        findView('bolos').content.blocks[2] = { type = 'table', id = 'bolo-list', title = Kora.lang('Terminal.current_and_recent_bolos'), searchable = true, pageSize = 12,
            columns = { { key = 'id', label = '#', sortable = true }, { key = 'status', label = Kora.lang('Terminal.status'), sortable = true },
                { key = 'kind', label = Kora.lang('Terminal.type'), sortable = true }, { key = 'subject', label = Kora.lang('Terminal.subject'), sortable = true },
                { key = 'title', label = Kora.lang('Terminal.alert') }, { key = 'expires', label = Kora.lang('Terminal.expires') } },
            rows = output, empty = Kora.lang('Terminal.no_bolos_found'), action = 'bolo:select', idKey = 'id' }
        return true
    end

    if policeAccess then
        refreshAll(refreshDashboard, refreshReports, refreshCases, refreshWarrants, refreshBolos)
    end

    Kora.nui.registerApp({
        id = 'kora_mdt:terminal', title = role == 'medical' and 'Medical Records Terminal' or 'Mobile Data Terminal',
        description = role == 'medical' and 'Patient and treatment records' or 'Law enforcement operations and records',
        icon = role == 'medical' and 'heart-pulse' or 'monitor-smartphone', width = 1240, height = 820,
        navigation = navigation, footer = Kora.lang('Terminal.every_record_is_permission_checked'),
        onAction = function(selectedId, context)
            local input = type(context and context.value) == 'table' and context.value or {}
            local itemId = context and context.itemId

            if selectedId == 'person:search' then
                local rows, err = Kora.callback.trigger('kora_mdt:server:searchPeople', input.query)
                if not rows then return message(false, nil, err) end
                return update('search', { title = Kora.lang('Terminal.citizen_search'), description = Kora.lang('Terminal.results_for', input.query), blocks = {
                    { type = 'actions', actions = lookupActions },
                    { type = 'table', id = 'people-results', searchable = true, pageSize = 12,
                        columns = { { key = 'citizenid', label = Kora.lang('Terminal.citizen_id'), sortable = true }, { key = 'name', label = Kora.lang('Terminal.name'), sortable = true },
                            { key = 'phone_number', label = Kora.lang('Terminal.phone') }, { key = 'last_updated', label = Kora.lang('Terminal.last_seen'), sortable = true } },
                        rows = rows, empty = Kora.lang('Terminal.no_citizens_matched'), action = 'person:select', idKey = 'citizenid' },
                } })
            elseif selectedId == 'person:select' and itemId then
                return openPerson(itemId)
            elseif selectedId == 'vehicle:search' and policeAccess then
                local rows, err = Kora.callback.trigger('kora_mdt:server:searchVehicles', input.query)
                if not rows then return message(false, nil, err) end
                return update('search', { title = Kora.lang('Terminal.vehicle_search'), description = Kora.lang('Terminal.results_for', input.query), blocks = {
                    { type = 'actions', actions = lookupActions },
                    { type = 'table', id = 'vehicle-results', searchable = true, pageSize = 12,
                        columns = { { key = 'plate', label = Kora.lang('Terminal.plate'), sortable = true }, { key = 'model', label = Kora.lang('Terminal.model'), sortable = true },
                            { key = 'owner_name', label = Kora.lang('Terminal.owner'), sortable = true }, { key = 'citizenid', label = Kora.lang('Terminal.citizen_id') }, { key = 'state', label = Kora.lang('Terminal.state'), sortable = true } },
                        rows = rows, empty = Kora.lang('Terminal.no_vehicles_matched'), action = 'vehicle:select', idKey = 'plate' },
                } })
            elseif selectedId == 'vehicle:select' and itemId and policeAccess then
                return openVehicle(itemId)
            elseif selectedId == 'charges:list' and policeAccess then
                local rows, err = Kora.callback.trigger('kora_mdt:server:charges')
                if not rows then return message(false, nil, err) end
                return showResult({ title = Kora.lang('Terminal.penal_code'), description = Kora.lang('Terminal.server_authorized_charge_catalogue'), blocks = { {
                    type = 'table', id = 'charges', searchable = true, pageSize = 12,
                    columns = { { key = 'code', label = Kora.lang('Terminal.code'), sortable = true }, { key = 'label', label = Kora.lang('Terminal.charge'), sortable = true },
                        { key = 'fine', label = Kora.lang('Terminal.fine'), align = 'right', sortable = true } }, rows = rows, empty = Kora.lang('Terminal.no_charges_configured'),
                } } })
            elseif selectedId == 'charge:refresh' and policeBoss then
                local rows, err = Kora.callback.trigger('kora_mdt:server:manageCharges')
                if not rows then return message(false, nil, err) end
                return update('charges', chargeManagementContent(rows))
            elseif selectedId == 'charge:create' and policeBoss then
                local ok, err = Kora.callback.trigger('kora_mdt:server:createCharge', input)
                if not ok then return message(false, nil, err) end
                setChargeOptions(Kora.callback.trigger('kora_mdt:server:charges') or {})
                local managed = Kora.callback.trigger('kora_mdt:server:manageCharges') or {}
                return update('charges', chargeManagementContent(managed), { tone = 'success', message = Kora.lang('Notify.charge_created') })
            elseif selectedId == 'charge:select' and policeBoss and itemId then
                local rows = Kora.callback.trigger('kora_mdt:server:manageCharges') or {}
                for _, charge in ipairs(rows) do
                    if tostring(charge.code) == tostring(itemId) then selectedCharge = charge; break end
                end
                if not selectedCharge then return message(false, nil, Kora.lang('Error.charge_not_found')) end
                return showResult(chargeContent(selectedCharge))
            elseif selectedId == 'charge:edit' and policeBoss and selectedCharge then
                local ok, err = Kora.callback.trigger('kora_mdt:server:updateCharge', selectedCharge.code, input.label, input.fine)
                if not ok then return message(false, nil, err) end
                setChargeOptions(Kora.callback.trigger('kora_mdt:server:charges') or {})
                for _, charge in ipairs(Kora.callback.trigger('kora_mdt:server:manageCharges') or {}) do
                    if tostring(charge.code) == tostring(selectedCharge.code) then selectedCharge = charge; break end
                end
                return showResult(chargeContent(selectedCharge), { tone = 'success', message = Kora.lang('Notify.charge_updated') })
            elseif selectedId == 'firearm:search' and policeAccess then
                local row, err = Kora.callback.trigger('kora_mdt:server:shopFirearm', input.serial)
                if not row then return message(false, nil, err or Kora.lang('Error.firearm_not_found')) end
                return showResult({ title = row.weapon_name or input.serial, description = Kora.lang('Terminal.firearm_registration'), blocks = { {
                    type = 'details', columns = 2, items = { { label = Kora.lang('Terminal.serial'), value = row.serial or input.serial },
                        { label = Kora.lang('Terminal.owner_citizen_id'), value = row.owner_citizenid }, { label = Kora.lang('Terminal.licence'), value = row.licence_number or '—' },
                        { label = Kora.lang('Terminal.purchased'), value = when(row.purchased_at, '—') } },
                } } })
            elseif selectedId == 'report:refresh' and policeAccess then
                local failure = refreshAll(refreshReports, refreshDashboard)
                if failure then return message(false, nil, Kora.lang('Error.could_not_refresh_reports', failure)) end
                return update('reports', nil, { tone = 'success', message = Kora.lang('Notify.reports_refreshed') })
            elseif selectedId == 'report:create' and policeAccess then
                local id, err = Kora.callback.trigger('kora_mdt:server:createReport', input)
                if not id then return message(false, nil, err) end
                local failure = refreshAll(refreshReports, refreshDashboard)
                return update('reports', nil, savedNotice(Kora.lang('Notify.incident_report_created', id), failure))
            elseif (selectedId == 'report:select' or selectedId == 'report:open-linked') and itemId and policeAccess then
                local row, err = Kora.callback.trigger('kora_mdt:server:report', itemId)
                if not row then return message(false, nil, err or Kora.lang('Error.report_not_found')) end
                selectedReport = row
                return showReport(row)
            elseif selectedId == 'report:close' and selectedReport and policeAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:closeReport', selectedReport.id)
                if not ok then return message(false, nil, err) end
                selectedReport.status = 'closed'
                return update('reports', nil, savedNotice(Kora.lang('Notify.report_closed'), refreshAll(refreshReports, refreshDashboard)))
            elseif selectedId == 'case:refresh' and policeAccess then
                local failure = refreshAll(refreshCases, refreshDashboard)
                if failure then return message(false, nil, Kora.lang('Error.could_not_refresh_cases', failure)) end
                return update('cases', nil, { tone = 'success', message = Kora.lang('Notify.cases_refreshed') })
            elseif selectedId == 'case:attach-report' and policeAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:linkCaseReport', input.case_id, input.report_id)
                if not ok then return message(false, nil, err) end
                return update('cases', nil, savedNotice(Kora.lang('Notify.report_attached_to_case'), refreshAll(refreshCases)))
            elseif selectedId == 'case:create' and policeAccess then
                local id, err = Kora.callback.trigger('kora_mdt:server:createCase', input)
                if not id then return message(false, nil, err) end
                local failure = refreshAll(refreshCases, refreshDashboard)
                local row = Kora.callback.trigger('kora_mdt:server:case', id)
                if row then selectedCase = row; return showResult(caseContent(row), savedNotice(Kora.lang('Notify.case_opened_add_reports_with', id), failure)) end
                return update('cases', nil, savedNotice(Kora.lang('Notify.case_opened', id), failure))
            elseif selectedId == 'case:select' and itemId and policeAccess then
                local row, err = Kora.callback.trigger('kora_mdt:server:case', itemId)
                if not row then return message(false, nil, err or Kora.lang('Error.case_not_found')) end
                selectedCase = row
                return showResult(caseContent(row))
            elseif selectedId == 'case:link-report' and selectedCase and policeAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:linkCaseReport', selectedCase.id, input.report_id)
                if ok then
                    local failure = refreshAll(refreshCases)
                    local row = Kora.callback.trigger('kora_mdt:server:case', selectedCase.id)
                    if row then selectedCase = row; return showResult(caseContent(row), savedNotice(Kora.lang('Notify.report_added_use_add_report'), failure)) end
                    return update('cases', nil, savedNotice(Kora.lang('Notify.report_linked_to_case'), failure))
                end
                return message(false, nil, err)
            elseif (selectedId == 'case:investigate' or selectedId == 'case:close' or selectedId == 'case:reopen') and selectedCase and policeAccess then
                local state = selectedId == 'case:investigate' and 'investigating' or selectedId == 'case:close' and 'closed' or 'open'
                local ok, err = Kora.callback.trigger('kora_mdt:server:updateCaseStatus', selectedCase.id, state)
                if not ok then return message(false, nil, err) end
                selectedCase.status = state
                return update('cases', nil, savedNotice(Kora.lang('Notify.case_marked', state), refreshAll(refreshCases, refreshDashboard)))
            elseif selectedId == 'warrant:refresh' and policeAccess then
                local failure = refreshAll(refreshWarrants, refreshDashboard)
                if failure then return message(false, nil, Kora.lang('Error.could_not_refresh_warrants', failure)) end
                return update('warrants', nil, { tone = 'success', message = Kora.lang('Notify.warrants_refreshed') })
            elseif selectedId == 'warrant:create' and policeAccess then
                local id, err = Kora.callback.trigger('kora_mdt:server:createWarrant', input)
                if not id then return message(false, nil, err) end
                return update('warrants', nil, savedNotice(Kora.lang('Notify.warrant_issued', id), refreshAll(refreshWarrants, refreshDashboard)))
            elseif selectedId == 'warrant:select' and itemId and policeAccess then
                selectedWarrant = nil
                for _, row in ipairs(Kora.callback.trigger('kora_mdt:server:warrants') or {}) do if tostring(row.id) == tostring(itemId) then selectedWarrant = row; break end end
                if not selectedWarrant then return message(false, nil, Kora.lang('Error.warrant_not_found')) end
                local actions = {}
                if selectedWarrant.status == 'active' then actions = {
                    { id = 'warrant:serve', label = Kora.lang('Terminal.mark_served'), icon = 'check-circle', variant = 'primary', confirm = Kora.lang('Terminal.mark_this_warrant_as_served') },
                    { id = 'warrant:revoke', label = Kora.lang('Terminal.revoke_warrant'), icon = 'x-circle', variant = 'destructive', confirm = Kora.lang('Terminal.revoke_this_warrant') },
                } end
                return showResult({ title = Kora.lang('Terminal.warrant', tostring(selectedWarrant.id)), description = tostring(selectedWarrant.reason or ''), actions = actions, blocks = { {
                    type = 'details', columns = 2, items = { { label = Kora.lang('Terminal.status'), value = tostring(selectedWarrant.status or Kora.lang('Terminal.unknown')) },
                        { label = Kora.lang('Terminal.subject'), value = tostring(selectedWarrant.subject_name or selectedWarrant.citizenid or Kora.lang('Terminal.unknown')) },
                        { label = Kora.lang('Terminal.citizen_id'), value = tostring(selectedWarrant.citizenid or '—') }, { label = Kora.lang('Terminal.expires'), value = when(selectedWarrant.expires_at, '—') },
                        { label = Kora.lang('Terminal.issued_by'), value = tostring(selectedWarrant.author_citizenid or Kora.lang('Terminal.unknown')) }, },
                } } })
            elseif (selectedId == 'warrant:serve' or selectedId == 'warrant:revoke') and selectedWarrant and policeAccess then
                local state = selectedId == 'warrant:serve' and 'served' or 'revoked'
                local ok, err = Kora.callback.trigger('kora_mdt:server:closeWarrant', selectedWarrant.id, state)
                if not ok then return message(false, nil, err) end
                selectedWarrant.status = state
                return update('warrants', nil, savedNotice(Kora.lang('Notify.warrant_marked', state), refreshAll(refreshWarrants, refreshDashboard)))
            elseif selectedId == 'bolo:refresh' and policeAccess then
                local failure = refreshAll(refreshBolos, refreshDashboard)
                if failure then return message(false, nil, Kora.lang('Error.could_not_refresh_bolos', failure)) end
                return update('bolos', nil, { tone = 'success', message = Kora.lang('Notify.bolos_refreshed') })
            elseif selectedId == 'bolo:create' and policeAccess then
                local id, err = Kora.callback.trigger('kora_mdt:server:createBolo', input)
                if not id then return message(false, nil, err or Kora.lang('Error.bolo_creation_failed')) end
                return update('bolos', nil, savedNotice(Kora.lang('Notify.bolo_created', id), refreshAll(refreshBolos, refreshDashboard)))
            elseif selectedId == 'bolo:select' and itemId and policeAccess then
                selectedBolo = nil
                for _, row in ipairs(Kora.callback.trigger('kora_mdt:server:bolos') or {}) do if tostring(row.id) == tostring(itemId) then selectedBolo = row; break end end
                if not selectedBolo then return message(false, nil, Kora.lang('Error.bolo_not_found')) end
                local actions = selectedBolo.status == 'active' and { { id = 'bolo:resolve', label = Kora.lang('Terminal.resolve_bolo'), icon = 'check-circle', variant = 'primary', confirm = Kora.lang('Terminal.resolve_this_bolo') } } or {}
                local details = { { label = Kora.lang('Terminal.status'), value = tostring(selectedBolo.status or Kora.lang('Terminal.unknown')) },
                    { label = Kora.lang('Terminal.type'), value = tostring(selectedBolo.subject_type or '—') }, { label = Kora.lang('Terminal.subject'), value = tostring(selectedBolo.subject_label or selectedBolo.subject_identifier or '—') },
                    { label = Kora.lang('Terminal.expires'), value = when(selectedBolo.expires_at, '—') }, { label = Kora.lang('Terminal.created_by'), value = tostring(selectedBolo.author_citizenid or Kora.lang('Terminal.unknown')) }, }
                if (C.bolo or {}).showLinkedCitizen ~= false and selectedBolo.subject_type == 'person' and selectedBolo.linked_citizenid then
                    table.insert(details, 4, { label = Kora.lang('Terminal.linked_citizen_id'), value = tostring(selectedBolo.linked_citizenid) })
                end
                return showResult({ title = Kora.lang('Terminal.bolo', tostring(selectedBolo.id), tostring(selectedBolo.title or Kora.lang('Terminal.untitled'))),
                    description = tostring(selectedBolo.description or ''), actions = actions, blocks = { {
                    type = 'details', columns = 2, items = details,
                } } })
            elseif selectedId == 'bolo:resolve' and selectedBolo and policeAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:resolveBolo', selectedBolo.id)
                if not ok then return message(false, nil, err) end
                selectedBolo.status = 'resolved'
                return update('bolos', nil, savedNotice(Kora.lang('Notify.bolo_resolved'), refreshAll(refreshBolos, refreshDashboard)))
            elseif selectedId == 'criminal:create' and criminalAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:addCriminal', input.citizenid, input.charge, input.notes)
                return message(ok, Kora.lang('Notify.criminal_record_saved'), err)
            elseif selectedId == 'medical:create' and medicalAccess then
                local ok, err = Kora.callback.trigger('kora_mdt:server:addMedical', input.citizenid, input.notes)
                return message(ok, Kora.lang('Notify.medical_record_saved'), err)
            elseif selectedId == 'analysis:start' and criminalAccess then
                Kora.events.trigger('kora_mdt:server:beginAnalysis', input.caseid)
                return { notice = { tone = 'primary', message = Kora.lang('Notify.ballistic_analysis_started') } }
            end
            return {}
        end,
    })
    Kora.nui.openApp('kora_mdt:terminal')
end

RegisterNetEvent('kora_mdt:client:open', openTerminal)
