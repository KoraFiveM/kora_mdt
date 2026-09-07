# qbmdt

`qbmdt` is the first-party qbcore2 records and operations terminal. It uses
qblib's AppShell, qbsql migrations, and server-owned role checks.

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

## Database

Migrations run automatically through qbsql when the resource starts. Version 2
adds reports, cases, warrants, BOLOs, report-to-case links, and the audit log.

## Tests

Run `./test/run.sh` from this resource. The smoke suite covers role enforcement,
bounded searches, report validation and audit behavior, warrant and BOLO state
transitions, weapon qualification, and evidence-analysis proof handling.

## Next parity areas

The next useful additions from larger MDT systems are multi-person/multi-charge
reports, evidence chain of custody, case assignment and notes, live dispatch and
unit status integration, impound history, personnel/FTO tools, and rank-based
permission management.
