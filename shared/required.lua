-- Required-field rules shared by the server (which enforces them) and the client
-- (which marks fields required and lets the form pre-validate them).
-- Fields marked `fixed` always stay required: the record cannot be stored without them.
-- Everything else follows Config.mdt.requiredFields[form][field]; the legacy
-- Config.mdt.reports.requireSubject / requireCharge options are aliases that also
-- make the matching report field required when set to true.
MdtRequired = {}

local fields = {
    report = {
        title = { label = 'Title', fixed = true },
        narrative = { label = 'Incident narrative', default = true },
        subject = { label = 'Subject citizen ID', default = false, legacy = 'requireSubject' },
        charge = { label = 'Charge', message = 'A charge is required.', default = false, legacy = 'requireCharge' },
    },
    case = {
        title = { label = 'Case title', fixed = true },
        summary = { label = 'Investigation summary', default = true },
    },
    warrant = {
        citizenid = { label = 'Citizen ID', fixed = true },
        reason = { label = 'Probable cause / reason', default = true },
    },
    bolo = {
        identifier = { label = 'Citizen ID, name or plate', fixed = true },
        title = { label = 'Alert title', fixed = true },
        description = { label = 'Description and instructions', default = true },
    },
    criminal = {
        citizenid = { label = 'Citizen ID', fixed = true },
        charge = { label = 'Charge', fixed = true },
        notes = { label = 'Notes', default = false },
    },
    medical = {
        citizenid = { label = 'Citizen ID', fixed = true },
        notes = { label = 'Treatment / notes', default = true },
    },
}

function MdtRequired.isRequired(form, field)
    local spec = fields[form] and fields[form][field]
    if not spec then return false end
    if spec.fixed then return true end
    local mdt = Config and Config.mdt or {}
    local configured = mdt.requiredFields and mdt.requiredFields[form]
    if configured and configured[field] ~= nil then
        if configured[field] == true then return true end
    elseif spec.default then
        return true
    end
    if spec.legacy and mdt.reports and mdt.reports[spec.legacy] == true then return true end
    return false
end

function MdtRequired.label(form, field)
    local spec = fields[form] and fields[form][field]
    return spec and spec.label or field
end

-- Returns a message naming the first required field that is empty, or nil.
-- `present` maps field name -> true when the submitted value is non-empty.
function MdtRequired.firstMissing(form, order, present)
    for _, field in ipairs(order) do
        if MdtRequired.isRequired(form, field) and not present[field] then
            return fields[form][field].message or ('%s is required.'):format(MdtRequired.label(form, field))
        end
    end
end
