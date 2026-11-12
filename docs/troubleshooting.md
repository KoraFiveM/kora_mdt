---
title: Troubleshooting
sidebar_position: 12
---

# Troubleshooting

## Common messages

| Message | Cause |
| --- | --- |
| "You must be on duty as police, EMS, or a judge to use the MDT." | The job is not in `roles`, or `requireOnDuty` is true and the player is off duty. |
| "MDT database is still starting. Try again shortly." | The schema is not ready yet; `kora_sql` or the `players` table was not available within 60 seconds. Check the console for `[kora_mdt]` lines. |
| "kora_core player schema unavailable; report creation will remain disabled." (console) | The `players` table did not appear. The boot thread stops and `kora_mdt:server:databaseReady` is never triggered, so charges and reports stay unavailable. |
| "Could not load reports: ..." (and similar) | A list query failed. The reason is also printed to the server console. |
| "Citizen ID not found" | A citizen ID containing a digit was submitted that does not exist (or is soft-deleted). |
| "More than one citizen is named ..." | Name resolution found several matches; use the citizen ID. |
| "speak to the store records clerk" | Firearm lookup in `npc` mode away from a clerk. |
| "The range targets could not be loaded." | `targetModel` could not be created on the client. |

## Known caveats and code discrepancies

- **Qualification minigame is not used.** `beginQualification` in `server/main.lua` is never called. The licence is issued as soon as the last training round is counted, so `Config.mdt.weaponLicence.qualification`, `kora_mdt:server:completeWeaponLicence` and `kora_mdt:client:weaponLicenceQualification` have no effect. The README and the QA scenario ("pass the skillbar") describe a step that does not happen.
- **`kora_dispatch` is declared but unused.** The manifest lists it as a dependency; no code here references it. The README's "live dispatch" item is listed only as a future area.
- **`player_vehicles` is an undeclared table dependency.** If it is missing, vehicle search silently returns an empty list and the vehicle record returns "not found".
- **Warrant wording.** The `warrantDefaultDays` description and the QA scenario name say judge, but police can also issue warrants (the server checks the police domain, which judges also pass).
- **Firearm registry in the terminal.** It always calls the clerk-gated callback, so it only works away from a clerk in `lookupMode = 'mdt'`. The clerk ped is spawned in both modes.
- **Unbounded option list.** `kora_mdt:server:reportOptions` has no `LIMIT` and returns every report to fill pickers, so it grows with the table.
- **No charge deactivation.** The `active` column is read but nothing sets it to 0; charges removed from `Config.mdt.charges` stay in the database.
- **Unused callback.** `kora_mdt:server:canManageCharges` is registered but not called by this resource.
- **README items not found in code.** The README mentions migrations at "version 4" and "version 5" and a one-time collation conversion guarded by `information_schema`. This repository has no migration code; the smoke test `test/smoke/collation.lua` asserts that startup only applies the schema. Any conversion would have to happen inside `kora_sql`, which was not checked.
- **QA feature file.** `tests/checklist-police-and-ems.feature` gives the item `weaponlicense` for the shop scenario, but the code reads the licence from player metadata and `kora_mdt_licences`, not from an item.
- **Not audited.** Weapon licence issuance, firearm registration and casing analysis write no audit row.
