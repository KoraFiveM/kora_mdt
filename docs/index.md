---
title: kora_mdt
sidebar_position: 1
---

# kora_mdt

`kora_mdt` is a role-gated records terminal for Kora servers. Police, judge and medical jobs open a `kora_lib` NUI app with the `/mdt` command and work with citizen and vehicle records, incident reports, cases, warrants, BOLOs, a charge catalogue, criminal and medical records and ballistic casing analysis. The resource also runs the Ammu-Nation weapon licence range and registers firearm purchases. Every read and write is authorised on the server; hiding a page in the client is not treated as authorisation.

Current version: see `version` in `fxmanifest.lua`.

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

## Installation

1. Place the resource in your resources folder and ensure it after its dependencies:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_inventory
   ensure kora_police
   ensure kora_target
   ensure kora_dispatch
   ensure kora_mdt
   ```

2. No SQL import is needed. On start the server waits up to 60 seconds for `kora_sql` and for the `players` table, creates any missing `kora_mdt_*` tables and seeds the charge catalogue. See [Database](./database.md).
3. Adjust [Configuration](./configuration.md), especially the job names in `Config.mdt.roles`.

## Command

| Command | Behaviour |
| --- | --- |
| `/mdt` (name set by `Config.mdt.command`) | Registered on the client without command restriction. It asks the server to open the terminal; the server replies with an error notification unless the player holds a configured job (and is on duty when `requireOnDuty` is true). Rate limit: 4 requests per 2 seconds. |

The resource exposes no exports and defines no ACE permissions. See [Permissions](./permissions.md).

## Testing

- `./test/run.sh` runs the offline Lua smoke tests in `test/smoke/` (plain Lua, no FiveM). It needs a `lua` binary, or set `LUA`.
- `tests/checklist-police-and-ems.feature` holds manual QA scenarios registered with `qa_feature` in `fxmanifest.lua`. Some of its steps are out of date, see [Troubleshooting](./troubleshooting.md).

## Pages

- [Features](./features.md) - what each terminal tab does and how records behave
- [Configuration](./configuration.md) - every `Config.mdt` option
- [Permissions](./permissions.md) - roles, duty checks and what each role can do
- [Firearms and licences](./firearms-and-licences.md) - weapon licence range, shop hook, firearm registry, records clerk
- [Events](./events.md) - net events, local events, callbacks and events used from other resources
- [Database](./database.md) - tables, columns and external tables read
- [Troubleshooting](./troubleshooting.md) - known caveats, dead options and common problems
