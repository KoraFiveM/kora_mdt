# kora_mdt

`kora_mdt` is the first-party qbcore2 records and operations terminal. It uses
kora_lib's AppShell, kora_sql (tables declared in `server/schema.lua`), and server-owned role checks.

## Current features

- Operations dashboard with open report, case, warrant, and BOLO counts
- Partial citizen search by name, citizen ID, or phone number
- Partial vehicle search by plate, model, owner, or citizen ID
- Citizen profiles with identity, licences, firearms, reports, warrants, BOLOs,
  criminal history, and role-gated medical history
- Vehicle records with ownership, garage/impound state, and active BOLOs
- Incident report creation, optional charge filing, viewing, and closure
- Investigation cases with priorities, linked incident reports, and status management
- Warrant creation, expiry, service, and revocation
- Person and vehicle BOLO creation, expiry, and resolution
- Penal-code and firearm-registry lookup
- Medical and criminal record entry
- Ballistic evidence analysis
- Ammu-Nation weapon qualification and automatic firearm sale registration
- Audit logging for operational record changes

## Access

Police, ambulance, and judge jobs are configured in `config.lua`. When
`requireOnDuty` is enabled, the server checks duty state for every callback and
event; hiding a page in the client is never treated as authorization.

## Reports and dates

- `Config.mdt.requiredFields` chooses which form fields must be filled in. The server enforces it and returns an error naming the missing field (for example "Subject citizen ID is required."); the terminal marks required fields with an asterisk and pre-validates the form. Defaults keep the previous behaviour:

  | Form | Option | Default |
  | --- | --- | --- |
  | Incident report | `report.subject` (existing citizen ID) | `false` |
  | Incident report | `report.charge` (catalogue charge) | `false` |
  | Incident report | `report.narrative` | `true` |
  | Case | `case.summary` | `true` |
  | Warrant | `warrant.reason` | `true` |
  | BOLO | `bolo.description` | `true` |
  | Criminal record | `criminal.notes` | `false` |
  | Medical record | `medical.notes` | `true` |

  Titles, citizen IDs / plates and the criminal-record charge are always required.
- `Config.mdt.reports.requireSubject` / `requireCharge` still work as aliases: if either the alias or the matching `requiredFields.report` entry is `true`, the field is required.
- Report subject and charge: `Config.mdt.reports.resolveSubjectByName` (default `true`) links a subject typed as an exact full name to that citizen when exactly one matches; `allowUnknownSubject` (default `true`) otherwise stores it as unlinked text, or rejects it with "Subject must be a citizen ID" when `false`; `allowCustomCharges` (default `true`) stores a charge outside the catalogue as text on the report (no criminal record is created), or rejects it when `false`. A mistyped citizen ID (contains a digit) is always rejected as not found.
- BOLOs show the subject exactly as typed (`kora_mdt_bolos.subject_text`). A Person subject that is an existing citizen ID or an exact, unique full name is also linked to that citizen (`subject_identifier`), so the BOLO appears on their profile; the link is never added to the Subject text (`Config.mdt.bolo.resolvePersonByName`, `allowUnknownPersonSubject`, `showLinkedCitizen` shows the link as a separate detail row). BOLOs saved before version 5 drop the old ` (CID)` suffix and show the linked citizen's name instead of a bare citizen ID. The version 4 migration adds `subject_text`, `charge_text` (reports) and `subject_label` (BOLOs, legacy).
- `Config.mdt.dateFormat` (default `YYYY-MM-DD HH:mm`; tokens `YYYY MM DD HH mm ss`) controls every date/time shown in the terminal.
- Every date column (any key ending in `_at`, plus `date`/`timestamp`) is formatted on the server whether the database layer returns a millisecond/second number, a string or a table; an unreadable value is dropped, never shown as `table: 0x...`.
- If a list (reports, cases, warrants, BOLOs, dashboard) cannot be loaded, the terminal shows the specific error instead of an empty table and the server console logs it with a `[kora_mdt]` prefix. Creating or closing a report, case, warrant or BOLO refreshes its list and the dashboard in the same response, and Refresh buttons confirm with a notice.

## Database

The schema is declared in `server/schema.lua` (`KoraMdtSchema`) and applied on start through
`Kora.sql.ensureTables`, which only adds what is missing.
Queries that join `kora_mdt_*` columns to external tables such as `players` pin
`COLLATE utf8mb4_unicode_ci` on both sides, so they work whatever collation the tables have.
Tables created before they declared `utf8mb4_unicode_ci` are converted once on start (guarded by
`information_schema`, a no-op when already aligned).

## Tests

Run `./test/run.sh` from this resource. The smoke suite covers role enforcement,
bounded searches, report validation and audit behavior, warrant and BOLO state
transitions, weapon qualification, and evidence-analysis proof handling.

## Next parity areas

The next useful additions from larger MDT systems are multi-person/multi-charge
reports, evidence chain of custody, case assignment and notes, live dispatch and
unit status integration, impound history, personnel/FTO tools, and rank-based
permission management.
