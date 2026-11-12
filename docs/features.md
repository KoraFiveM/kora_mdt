---
title: Features
sidebar_position: 6
---

# Features

The terminal is a `kora_lib` NUI app (`kora_mdt:terminal`). The tabs shown depend on the role, see [Permissions](./permissions.md). All data comes from server callbacks listed in [Events](./events.md).

## Dashboard (police, judge)

Counts of open reports, open cases (any status except closed), active warrants (not expired) and active BOLOs (not expired), plus the 8 most recently updated reports.

## Search

- **Search citizens** (all roles; labelled "Search patients" for a medical-only role). Needs at least 2 characters and matches name, citizen ID or phone number by substring. Results are limited by `Config.mdt.operations.searchLimit`.
- **Search vehicles** (police, judge). Matches plate, model, owner citizen ID or owner name in `player_vehicles`, limited by `searchLimit`.
- **Penal code** (police, judge). Lists the active charges with their fines.
- **Firearm registry** (police, judge). Looks up a serial. In the default `npc` lookup mode this only works while standing at a records clerk, see [Firearms and licences](./firearms-and-licences.md).

## Citizen profile

Identity (citizen ID, phone, date of birth, nationality, job, driver licence from player metadata, weapon licence number) and a timeline of linked records. Police and judge also see registered firearms, criminal record, up to 25 reports naming the citizen as subject, active warrants and active BOLOs. Medical and judge roles also see medical records.

## Vehicle record

Plate, model, owner, citizen ID, state, garage or impound lot, and active vehicle BOLOs.

## Incident reports (police, judge)

- Create a report with title, optional subject, optional charge and narrative. Which optional fields are mandatory is set by `Config.mdt.requiredFields` (title is always required).
- The subject may be a citizen ID, or a full name. With `resolveSubjectByName` an exact, case-insensitive name matching exactly one citizen is linked; several matches are rejected. Otherwise the subject is stored as free text, or rejected when `allowUnknownSubject` is false. A value that looks like a citizen ID (contains a digit) but does not exist is always rejected.
- The charge may be picked from the catalogue (matched by code or label). Other text is stored as free text on the report, or rejected when `allowCustomCharges` is false.
- When the charge is a catalogue charge and the subject is a linked citizen, a criminal record entry with the note "Report #id: title" is also created.
- Reports are listed (open first), viewed in a detail tab, and can be closed (only open to closed; there is no reopen).

## Cases (police, judge)

- Open a case with title, priority (low, normal, high, critical) and summary. The creating officer becomes the lead. Cases can be created with initial report links by the server callback, the terminal form does not offer that.
- Attach reports to a case from the Cases tab or from the case detail. A report already linked is rejected.
- Case detail has a timeline of linked reports. Status actions: Begin investigation (open to investigating), Close case, Reopen case (sets status back to open).

## Warrants (police, judge)

- Issue a warrant for an existing citizen ID with a reason and duration in days (default and maximum from `operations`).
- Warrants whose expiry has passed show as `expired` in the list.
- An active, unexpired warrant can be marked served or revoked. Nothing else changes a warrant.

## BOLOs (police, judge)

- Person or vehicle subject, alert title, description and duration in days.
- The Subject column always shows exactly what was typed. A person subject that is an existing citizen ID or a unique exact full name is also linked to that citizen, so the BOLO appears on the profile. Plates are stored upper-case.
- `Config.mdt.bolo` controls name resolution, free-text subjects and whether a "Linked citizen ID" row is shown.
- Active BOLOs can be resolved. Expired ones show as `expired`.

## Tools (police, judge)

- **Add criminal record**: citizen ID, charge (catalogue code or label) and notes.
- **Analyse ballistic casing**: see below.

## Charge management (police boss only)

A Charges tab for police jobs whose player has the boss flag. Create a charge (code, name, fine up to 2000000000) or edit the name and fine of an existing one. Codes are upper-cased and may contain letters, digits, `_` and `-`. There is no UI to deactivate or delete a charge.

## Medical records (medical, judge)

Add a medical record (citizen ID and notes). Records show in the patient profile for medical and judge roles.

## Ballistic casing analysis

Starting an analysis requires a case ID matching the `info.caseId` of a `filled_evidence_bag` item in the player's inventory. The player then completes the stages in `Config.mdt.analysis.stages` (default skillbar, circuit, pinpad) within `analysis.ttl`. Each stage uses a one-use `kora_lib` minigame proof issued by the server; the pinpad PIN is generated on the server. On success the server looks up the casing with `exports.kora_police:GetBallisticCasing` and the client shows a notice with the case, weapon and weapon serial. Nothing is written to the database.

## Dates

Every date shown is formatted on the server using `Config.mdt.dateFormat`. Unreadable values are dropped instead of showing a raw table.

## Errors and audit log

- If a list cannot load, the terminal shows the error text and the server console prints a line prefixed `[kora_mdt]`.
- After creating or closing a report, case, warrant or BOLO the list and dashboard are refreshed in the same action; a failed refresh is reported in the notice.
- Operational changes are written to `kora_mdt_audit_log`. Audited actions: `charge.create`, `charge.update`, `criminal.create`, `medical.create`, `report.create`, `report.close`, `case.create`, `case.status`, `case.report.link`, `warrant.create`, `warrant.served`, `warrant.revoked`, `bolo.create`, `bolo.resolve`. Weapon licence issuance, firearm registration and casing analysis are not audited. The log is written only; the terminal has no view for it.
