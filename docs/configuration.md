---
title: Configuration
sidebar_position: 7
---

# Configuration

All options live in `config.lua` under `Config.mdt`. Most are registered with `kora_lib` (`Kora.config.adopt`) so they can be edited through its configuration tooling; `.gitignore` excludes `config.local.lua`, described there as generated per-server `kora_lib` configuration overrides.

## Core

| Option | Default | Description |
| --- | --- | --- |
| `command` | `mdt` | Client command that opens the terminal. |
| `dateFormat` | `YYYY-MM-DD HH:mm` | Display format. Tokens: `YYYY`, `MM`, `DD`, `HH`, `mm`, `ss`. |

## `roles`

| Option | Default | Description |
| --- | --- | --- |
| `policeJobs` | `police = true` | Job names with police access. |
| `medicalJobs` | `ambulance = true` | Job names with medical access. |
| `judgeJobs` | `judge = true` | Job names with judge access (all police and medical features). |
| `requireOnDuty` | `true` | Require the job to be on duty for every callback and event. |

A job listed in several tables gets the first match in the order judge, police, medical. See [Permissions](./permissions.md).

## `operations`

| Option | Default | Description |
| --- | --- | --- |
| `searchLimit` | `25` | Maximum rows for person and vehicle searches. |
| `recentLimit` | `50` | Maximum rows for the reports, cases, warrants and BOLOs lists. |
| `warrantDefaultDays` | `7` | Prefilled warrant duration; also used when the submitted value is not a number. |
| `warrantMaxDays` | `30` | Maximum warrant duration (submitted values are clamped to 1 through this). |
| `boloDefaultDays` | `7` | Prefilled BOLO duration. |
| `boloMaxDays` | `30` | Maximum BOLO duration. |

## `reports`

| Option | Default | Description |
| --- | --- | --- |
| `requireSubject` | `false` | Legacy alias of `requiredFields.report.subject`. If either is true the subject is required. |
| `requireCharge` | `false` | Legacy alias of `requiredFields.report.charge`. |
| `resolveSubjectByName` | `true` | Match a non-ID subject to a citizen by exact full name when exactly one matches. |
| `allowUnknownSubject` | `true` | Store an unmatched subject as free text; when false reject it with "Subject must be a citizen ID". |
| `allowCustomCharges` | `true` | Store a charge outside the catalogue as free text (no criminal record is created); when false reject it. |

## `requiredFields`

Which optional fields must be filled in. The server enforces this and names the missing field; the terminal marks the field as required.

| Option | Default |
| --- | --- |
| `report.subject` | `false` |
| `report.charge` | `false` |
| `report.narrative` | `true` |
| `case.summary` | `true` |
| `warrant.reason` | `true` |
| `bolo.description` | `true` |
| `criminal.notes` | `false` |
| `medical.notes` | `true` |

Always required and not configurable: report title, case title, warrant citizen ID, BOLO subject and title, criminal record citizen ID and charge, medical record citizen ID.

## `bolo`

| Option | Default | Description |
| --- | --- | --- |
| `resolvePersonByName` | `true` | Link a person BOLO typed as an exact unique full name to that citizen. |
| `allowUnknownPersonSubject` | `true` | Store an unmatched person subject as free text; when false reject it. |
| `showLinkedCitizen` | `true` | Show a separate "Linked citizen ID" row in the BOLO detail. |

## `charges`

Seed list of `code`, `label` and `fine`. Rows are inserted with `INSERT IGNORE` once the database is ready, so existing codes are never changed and removing a row from the config does not remove it from the database. Defaults: `SPD-01` Speeding (250), `WPN-01` Unlawful discharge of a firearm (1500), `WPN-02` Possession of an unlicensed firearm (2500), `VEH-01` Reckless driving (750). Boss users can add and edit charges in the terminal.

## `analysis`

| Option | Default | Description |
| --- | --- | --- |
| `ttl` | `300000` | Milliseconds allowed to finish all stages. |
| `stages` | skillbar, circuit, pinpad (each `attempts = 1`) | Ordered minigame stages. Each row needs `game` and `opts`. A `pinpad` stage gets a server-generated 4-digit PIN. |

## `firearms`

| Option | Default | Description |
| --- | --- | --- |
| `shopId` | `ammunation` | Inventory shop whose weapon purchases need a weapon licence and are registered. Must match the shop ID from `kora_inventory`. |
| `lookupMode` | `npc` | `npc` (records clerk) or `mdt` (terminal lookup). |
| `shopRecords` | one clerk at `23.24, -1105.29, 29.80, 159.43` | Records clerk positions (`coords` vector4 and `label`). |

## `weaponLicence`

| Option | Default | Description |
| --- | --- | --- |
| `weapon` | `weapon_pistol` | Training weapon issued for the test. |
| `shots` | `10` | Training rounds issued and shots required. |
| `trainingTimeout` | `120000` | Milliseconds before the session ends as failed. |
| `targetModel`, `targetHeading` | `prop_target_blue_arrow`, `180.0` | Prop and heading of the spawned targets. |
| `range` | `22.5, -1104.5, 29.8` | Origin to which `targetOffsets` are added. |
| `targetOffsets` | three vector3 offsets | One target prop is spawned per offset. |
| `zone.points`, `zone.thickness` | Ammu-Nation interior polygon, `4.0` | Building footprint; leaving it cancels the session. |
| `interactionPoint`, `interactionRadius` | counter point, `1.5` | Sphere target for the counter. If `interactionPoint` is nil the whole polygon is targeted. |
| `interactionDistance` | `2.0` | Target distance; also the padding around the polygon in the server start check. |
| `qualification` | skillbar options | Currently unused, see [Troubleshooting](./troubleshooting.md). |

See [Firearms and licences](./firearms-and-licences.md) for the full flow.
