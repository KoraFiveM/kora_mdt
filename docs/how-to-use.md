---
title: "How to use"
sidebar_position: 3
---


# How to use

Kora MDT has no exports of its own — every interaction goes through the `/mdt` command, server callbacks (`Kora.callback.register('kora_mdt:server:*')`) and a handful of net/local events. The client NUI (`client/terminal.lua`) is a pure presentation layer: it never decides who may see or change a record.

## Opening the terminal

Players run the configured command (`/mdt` by default). The client only forwards the request; the server decides whether the terminal opens at all.

```text title="open flow"
-- client/main.lua
RegisterCommand(C.command, function()
    local ok, err = Kora.events.trigger('kora_mdt:server:open')
    if not ok then notify(err or 'The MDT could not be reached.', 'error') end
end, false)

-- server/main.lua
Kora.events.register('kora_mdt:server:open', function(src)
    local userRole = role(src)   -- re-derived from kora_core job/duty, never trusted from the client
    if not userRole then
        return Kora.notify.send(src, { title = 'MDT', message = 'You must be on duty as police, EMS, or a judge to use the MDT.', type = 'error' })
    end
    TriggerClientEvent('kora_mdt:client:open', src, userRole, isPoliceBoss(src))
end, { rateLimit = { max = 4, window = 2000 } })
```

- There is no client-side role check before the request is sent — `role(src)` on the server is the only gate, and it is re-derived from `exports.kora_core:getJob(src)` on every call, never cached or trusted from the client.
- With `Config.mdt.roles.requireOnDuty = true` (the default), an authorised job must also be on duty or `role()` returns `nil` and the open is refused with a notification.
- A judge job is treated as having every domain’s access: `can(src, domain)` returns true when `role(src) == 'judge'` or `role(src) == domain`. Only one role is ever returned per player — the check order is judge, then police, then medical, so a job listed in more than one map resolves to the first match.
- `kora_mdt:server:open` is rate-limited (max 4 per 2s) to blunt spam-opening.

## Permissions and the audit log

This is a heavily server-checked resource: every single data-returning or data-changing callback re-derives the caller’s role (or, for charge management, whether they are a police boss) before doing anything — the NUI never carries an authority flag the server trusts.

```text title="server/main.lua — role derivation"
local function role(src)
    local job = exports.kora_core:getJob(src) or {}
    if C.roles.requireOnDuty and job.onduty ~= true then return nil end
    if C.roles.judgeJobs[job.name] then return 'judge' end
    if C.roles.policeJobs[job.name] then return 'police' end
    if C.roles.medicalJobs[job.name] then return 'medical' end
    return nil
end
local function can(src, domain) local r = role(src); return r == 'judge' or r == domain end
```

- `can(src, 'police')` gates vehicle search, reports, cases, warrants, BOLOs, criminal records and ballistic analysis. `can(src, 'medical')` gates medical records. `role(src)` alone (any of the three) gates citizen search and the person lookup, which then reveals different sections depending on which role it is (criminal/warrants/BOLOs/firearms for police or judge; medical history for medical or judge).
- `isPoliceBoss(src)` is separate from `role()`: it additionally requires the job to literally be a `policeJobs` job (not judge) and `job.isboss == true` (or `job.grade.isboss == true`), still subject to the on-duty check. It gates creating/editing penal-code charges (`kora_mdt:server:canManageCharges`, `manageCharges`, `createCharge`, `updateCharge`).
- Every mutating callback calls `audit(src, action, targetType, targetId, details)`, which resolves the actor’s citizen ID server-side and inserts a row into `kora_mdt_audit_log`. Audited actions: `charge.create`, `charge.update`, `criminal.create`, `medical.create`, `report.create`, `report.close`, `case.create`, `case.status`, `case.report.link`, `warrant.create`, `warrant.served`/`warrant.revoked`, `bolo.create`, `bolo.resolve`. Read-only callbacks (search, dashboard, person/vehicle lookup, firearm lookup) are not audited.
- Input is sanitised before it reaches SQL: `cleanCid` only accepts `%w%-` characters, `cleanText` strips control characters and trims/truncates, `cleanId` coerces to a positive integer, and every query is parameterised (no string-built SQL from player input). `missingRequired` (backed by `shared/required.lua`’s `MdtRequired`) enforces per-form required fields from `Config.mdt.requiredFields`, with a few fields (titles, citizen IDs/plates, the criminal charge) always required regardless of config.

## Records, reports, cases, warrants and BOLOs

- Citizen search (`kora_mdt:server:searchPeople`) and the person record (`kora_mdt:server:person`) are available to any of the three roles; the person record’s criminal/firearms/reports/warrants/BOLOs block is only populated for police/judge, and its medical block only for medical/judge.
- Vehicle search and the vehicle record are police/judge only, and include active BOLOs matched on plate.
- Creating an incident report (`kora_mdt:server:createReport`) resolves the subject: a well-formed citizen ID that exists is used as-is; otherwise, if `Config.mdt.reports.resolveSubjectByName` allows it, an exact case-insensitive full-name match is looked up — a unique match links the citizen, several matches are rejected (asks for a citizen ID instead), and with `allowUnknownSubject` off an unmatched subject is rejected outright (otherwise it is stored as free text). The same resolution shape (resolve-by-name / allow-unknown) is reused for BOLO person subjects via `Config.mdt.bolo`. Charges follow the same pattern against the charge cache, controlled by `Config.mdt.reports.allowCustomCharges`.
- If a report both links a known subject and a catalogue charge, the server also writes a matching `kora_mdt_criminal_records` entry referencing the report (`"Report #<id>: <title>"`).
- Cases link to reports through `kora_mdt_case_reports`; warrants and BOLOs have configurable default/maximum durations (`Config.mdt.operations`) and are clamped server-side regardless of what the client sends.
- BOLOs store the officer-typed text verbatim as the shown Subject (`subject_text`) separately from the resolved lookup key (`subject_identifier`); `Config.mdt.bolo.showLinkedCitizen` additionally reveals a linked citizen ID in the BOLO detail view when one was resolved.

## Firearms: licensing and the registry

A weapon licence is required to buy from the configured civilian shop, and purchases there are written to a registry.

- `exports.kora_inventory:RegisterHook('buyItem', ...)` blocks a purchase from `Config.mdt.firearms.shopId` (default `ammunation`) of any item in the `weapons` shared table unless `hasWeaponLicense(src)` — the player’s `metadata.licences.weapon` flag **and** a matching row in `kora_mdt_licences` both have to be true.
- The same hook also rejects any purchase from that shop where the item count is not 1 (`server/main.lua:194`); a blocked purchase without a licence shows "You need a weapon licence to purchase firearms.". See [Firearms and licences](./firearms-and-licences.md) for the full shop and clerk behaviour.
- On `kora_inventory:server:itemPurchased` from that shop, the server writes the sale to `kora_mdt_firearms` (serial, weapon name, owner, licence number, shop id). A later transfer of the same item never rewrites this row — it stays the original purchase record.
- Looking up a firearm by serial (`kora_mdt:server:shopFirearm`) depends on `Config.mdt.firearms.lookupMode`: `'npc'` requires the player to be near one of the configured `shopRecords` clerks (a static, invincible ped spawned client-side with a `kora_target` option); `'mdt'` instead requires police/judge access and exposes the lookup from the terminal’s Firearm registry action.

## Weapon licence: how it actually behaves

The config defines a `qualification` minigame (e.g. a skillbar) and the server has `beginQualification`/`completeWeaponLicence` functions clearly built for a qualification step after the live-fire portion. In the code as it runs today, that step is never reached — firing the required number of training rounds finishes and issues the licence directly.

```lua title="server/main.lua"
-- The live-fire test is the whole test. Once every issued round has
-- landed, the licence is issued immediately:
AddEventHandler('kora_inventory:server:trainingRoundFired', function(src, round)
    local state = training[src]
    if not state or type(round) ~= 'table' or round.owner ~= GetCurrentResourceName()
        or round.weapon ~= C.weaponLicence.weapon or round.shot ~= state.shots + 1 then return end
    if not stillEligible(src, state) then return finishTraining(src, state, false) end

    state.shots = round.shot
    if state.shots >= C.weaponLicence.shots then finishTraining(src, state, true) end
end)
```

1. **Start** — The player uses the range’s `kora_target` option (or, with no `interactionPoint` configured, walks into the whole zone polygon) to trigger `kora_mdt:server:startWeaponLicence`. The server checks: no session already running, the player is within `interactionDistance` of the range, their citizen ID is known, and they don’t already hold a weapon licence. It then starts a temporary training weapon via `exports.kora_inventory:StartTrainingWeapon(src, weapon, shots)`.

2. **Targets and session watch** — The client spawns the configured number of static target props at `range + targetOffsets`, and watches a polygon zone (`Config.mdt.weaponLicence.zone`) for the player leaving the building; leaving removes the temporary weapon locally and tells the server to cancel the session. A server-side `trainingTimeout` also force-ends the session if it runs too long.

3. **Firing rounds** — Each shot arrives server-side as `kora_inventory:server:trainingRoundFired`, validated against the expected weapon, the next sequential shot number, and `stillEligible` (not expired, same citizen ID, same routing bucket, still physically inside the zone). Once `state.shots` reaches the configured `shots` count, `finishTraining(src, state, true)` runs immediately — there is no further step, no qualification prompt, and no separate pass/fail judgement beyond having fired every round while still eligible.

4. **Issuing the licence** — `finishTraining` stops the training weapon and, on a pass, calls `issueWeaponLicence`: it generates a licence number (`WPN-<last 6 of citizen ID>-<random 4 digits>`), upserts it into `kora_mdt_licences`, and sets `metadata.licences.weapon = true` via `exports.kora_core:setMetaData`. The client is told whether it passed and how many shots were fired.

> **Note:** Dead code found during review and confirmed against the current source: `beginQualification` and the `kora_mdt:server:completeWeaponLicence` event both depend on `state.authorization`, which only `beginQualification` ever sets — and nothing in the resource calls `beginQualification` (confirmed by searching the whole resource for call sites; only its own definition exists). So `completeWeaponLicence` can never succeed and the client’s `kora_mdt:client:weaponLicenceQualification` listener is never triggered by the server. In practice, no qualification minigame is ever shown to the player; only the live-fire round count decides the outcome.

## Ballistic evidence analysis

A separate, police-only three-stage minigame flow tied to `kora_police`’s ballistic casing data.

- `kora_mdt:server:beginAnalysis(caseId)` requires `can(src, 'police')` and that the player is carrying a `filled_evidence_bag` item (via `exports.kora_inventory:GetItemsByName`) whose `info.caseId` matches. It then authorises the first configured stage via `Kora.minigames.authorizeProof` and sends the client a one-use authorization token.
- Each configured stage in `Config.mdt.analysis.stages` (by default: skillbar, circuit, then a pinpad whose PIN is generated server-side) must be played and its proof submitted back and consumed (`Kora.minigames.consumeProof`) before the next stage is authorised; the whole sequence must finish within `Config.mdt.analysis.ttl` milliseconds or the state is dropped.
- After the last stage, the server reads `exports.kora_police:GetBallisticCasing(caseId)` and sends the linked weapon serial/name to the client as the analysis result.
