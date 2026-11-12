---
title: Database
sidebar_position: 11
---

# Database

## Setup

`server/boot.lua` waits for `kora_sql` (60 s) and for the `players` table (60 s, created by `kora_core`), then calls `Kora.sql.ensureTables(KoraMdtSchema)`, which only adds what is missing. Schema warnings are printed with a `[kora_mdt]` prefix. All tables declare `utf8mb4_unicode_ci`, and joins between `kora_mdt_*` and external tables pin `COLLATE utf8mb4_unicode_ci` on both sides.

## Tables

| Table | Purpose | Key columns |
| --- | --- | --- |
| `kora_mdt_licences` | Issued licences | `citizenid` + `licence_type` (primary), unique `licence_number`, `issued_at` |
| `kora_mdt_firearms` | Firearm registry | `serial` (primary), `weapon_name`, `owner_citizenid`, `licence_number`, `shop_id`, `purchased_at` |
| `kora_mdt_charges` | Charge catalogue | `code` (primary), `label`, `fine`, `active` |
| `kora_mdt_criminal_records` | Criminal history | `id`, `citizenid`, `charge_code`, `notes` (nullable, 1000), `author_citizenid`, `created_at` |
| `kora_mdt_medical_records` | Medical notes | `id`, `citizenid`, `notes` (1000), `author_citizenid`, `created_at` |
| `kora_mdt_reports` | Incident reports | `id`, `title`, `narrative`, `status` (`open`, `closed`), `subject_citizenid`, `subject_text`, `charge_code`, `charge_text`, `author_citizenid`, `created_at`, `updated_at` |
| `kora_mdt_cases` | Investigations | `id`, `title`, `summary`, `priority` (`low`, `normal`, `high`, `critical`), `status` (`open`, `investigating`, `closed`), `lead_citizenid`, timestamps |
| `kora_mdt_case_reports` | Case to report links | `case_id` + `report_id` (primary) |
| `kora_mdt_warrants` | Warrants | `id`, `citizenid`, `reason`, `status` (`active`, `served`, `revoked`), `author_citizenid`, `closed_by_citizenid`, `expires_at`, timestamps |
| `kora_mdt_bolos` | BOLOs | `id`, `subject_type` (`person`, `vehicle`), `subject_identifier`, `subject_text`, `subject_label` (legacy), `title`, `description`, `status` (`active`, `resolved`), `author_citizenid`, `expires_at`, timestamps |
| `kora_mdt_audit_log` | Audit trail | `id`, `actor_citizenid`, `action`, `target_type`, `target_id`, `details`, `created_at` |

Notes:

- Expiry is computed on the server with `NOW()`; `expired` is a displayed status, not stored.
- `subject_text` and `charge_text` hold text typed by the officer when it did not resolve to a citizen or catalogue charge. For BOLOs `subject_text` is what is displayed and `subject_identifier` is the lookup key. `subject_label` is only read as a fallback for old rows.

## External tables read

| Table | Columns used | Owner |
| --- | --- | --- |
| `players` | `citizenid`, `name`, `phone_number`, `charinfo`, `job`, `metadata`, `last_updated`, `deleted_at` | `kora_core` |
| `player_vehicles` | `plate`, `model`, `citizenid`, `state`, `garage_id`, `impound_lot`, `deleted_at` | not declared; supplied by the vehicle resource of the server |

The resource only reads these tables. It does not wait for `player_vehicles` at start.
