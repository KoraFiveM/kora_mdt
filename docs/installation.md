---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora MDT is a role-gated terminal: a single NUI app that shows different tabs for police, EMS and judge characters, backed entirely by server-checked callbacks. It is server- and client-paired (no standalone client logic reaches the database) and depends on seven other Kora resources.

## Install Kora MDT

1. **Add the folder and its dependencies** — Place `kora_mdt` in `resources/[kora]`. It declares `dependency` on `kora_lib`, `kora_sql`, `kora_core`, `kora_inventory`, `kora_police`, `kora_target` and `kora_dispatch` — all seven must be present and started first.

   ```lua title="fxmanifest.lua"
   fx_version 'cerulean'
   game 'gta5'
   lua54 'yes'

   name 'kora_mdt'

   dependency 'kora_lib'
   dependency 'kora_sql'
   dependency 'kora_core'
   dependency 'kora_inventory'
   dependency 'kora_police'
   dependency 'kora_target'
   dependency 'kora_dispatch'
   ```

2. **Start order** — Ensure the dependencies before `kora_mdt` in `server.cfg`.

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_police
   ensure kora_target
   ensure kora_dispatch
   ensure kora_mdt
   ```

3. **Wait for the database** — `server/boot.lua` waits for `Kora.sql.ready(60000)`, then for `kora_core`’s `players` table via `Kora.sql.awaitTables({ 'players' })` (report creation looks up `players.deleted_at`), then runs `Kora.sql.ensureTables(KoraMdtSchema)` to create or update every MDT table. If any step fails it prints an error and the resource does not continue (reports stay disabled). On success it fires the local event `kora_mdt:server:databaseReady`.

4. **Set roles and duty requirement** — Edit `Config.mdt.roles` to list which job names count as police, medical or judge, and whether on-duty is required. These are the only jobs that can ever open or use the terminal — everything else in the resource is gated behind this.

   ```lua title="config.lua"
   Config.mdt = {
       command = 'mdt',
       roles = {
           policeJobs = { police = true },
           medicalJobs = { ambulance = true },
           judgeJobs = { judge = true },
           requireOnDuty = true,
       },
       -- ...
   }
   ```

5. **Review the weapon-licence range and firearm shop settings** — If your map places Ammu-Nation or its firing range differently, update `Config.mdt.weaponLicence` (range origin, target offsets, zone polygon, interaction point) and `Config.mdt.firearms.shopRecords` (NPC records-clerk coordinates) to match. See How to use for what these actually drive.

## Database schema

`server/schema.lua` defines eleven tables, applied through `Kora.sql.ensureTables` on boot (existing data is kept; only missing tables/columns/indexes are added).

- `kora_mdt_licences` — one row per `(citizenid, licence_type)`; currently only `licence_type = 'weapon'` is ever written. `licence_number` is unique.
- `kora_mdt_firearms` — the firearm retail/registry record: `serial` (primary key), `weapon_name`, `owner_citizenid`, `licence_number`, `shop_id`, `purchased_at`. A transfer never rewrites this row — it is the original purchase record.
- `kora_mdt_charges` — the penal code: `code` (primary key), `label`, `fine`, `active`. Seeded from `Config.mdt.charges` on `kora_mdt:server:databaseReady` with `INSERT IGNORE` (existing rows with the same code are left alone), then cached in memory.
- `kora_mdt_criminal_records` / `kora_mdt_medical_records` — per-citizen free-text entries with `author_citizenid` and timestamps.
- `kora_mdt_reports` — incident reports with an optional linked `subject_citizenid` or free-text `subject_text`, and an optional linked `charge_code` or free-text `charge_text`.
- `kora_mdt_cases` and `kora_mdt_case_reports` — investigations and their many-to-many link to reports.
- `kora_mdt_warrants` — status `active | served | revoked`, with `expires_at` and `closed_by_citizenid`.
- `kora_mdt_bolos` — `subject_type` `person | vehicle`, with both the officer-typed `subject_text` (always shown as the Subject) and a resolved `subject_identifier` used for lookups.
- `kora_mdt_audit_log` — append-only: `actor_citizenid`, `action`, `target_type`, `target_id`, `details`, `created_at`. See Permissions and the audit log below.

## Requirements

Declared in `fxmanifest.lua` (`dependency`):

| Resource | Used for |
| --- | --- |
| `kora_lib` | `Kora.nui` app shell, callbacks, rate-limited events, notifications, zones, entities, minigame proofs, config registration |
| `kora_sql` | Table creation (`Kora.sql.ensureTables`) and all queries |
| `kora_core` | Player data, job and duty state, shared weapon definitions, player metadata (`licences`) |
| `kora_inventory` | Shop purchase hook and event, training weapon, evidence bag lookup |
| `kora_police` | `GetBallisticCasing` export used by casing analysis |
| `kora_target` | Weapon licence counter and records clerk interactions |
| `kora_dispatch` | Declared in the manifest, but no code in this resource uses it (see [Troubleshooting](./troubleshooting.md)) |

Also required at runtime but not declared: the `players` table (created by `kora_core`; the resource waits for it) and a `player_vehicles` table for vehicle lookups. See [Database](./database.md).

## Startup behaviour

No SQL import is needed. On start the server waits up to 60 seconds for `kora_sql` and for the `players` table, creates any missing `kora_mdt_*` tables and seeds the charge catalogue. Schema warnings are printed with a `[kora_mdt]` prefix. See [Database](./database.md) for the full column list and [Configuration](./configuration.md) for every option.

## Testing

- `./test/run.sh` runs the offline Lua smoke tests in `test/smoke/` (plain Lua, no FiveM). It needs a `lua` binary, or set `LUA`.
- `tests/checklist-police-and-ems.feature` holds manual QA scenarios registered with `qa_feature` in `fxmanifest.lua`. Some of its steps are out of date, see [Troubleshooting](./troubleshooting.md).
