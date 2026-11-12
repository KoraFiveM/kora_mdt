---
title: kora_mdt
sidebar_position: 1
---

# kora_mdt

`kora_mdt` is a role-gated records terminal for Kora servers. Police, judge and medical jobs open a `kora_lib` NUI app with the `/mdt` command and work with citizen and vehicle records, incident reports, cases, warrants, BOLOs, a charge catalogue, criminal and medical records and ballistic casing analysis. The resource also runs the Ammu-Nation weapon licence range and registers firearm purchases. Every read and write is authorised on the server; hiding a page in the client is not treated as authorisation.

Current version: see `version` in `fxmanifest.lua`.

## Documentation map

- [Installation](./installation.md) - dependencies, start order, database wait, roles, requirements table and tests
- [How to use](./how-to-use.md) - opening the terminal, permissions and audit log, records, firearms licensing, weapon licence range, ballistic analysis
- [Commands](./commands.md) - the `/mdt` command
- [Features](./features.md) - what each terminal tab does and how records behave
- [Configuration](./configuration.md) - every `Config.mdt` option
- [Permissions](./permissions.md) - roles, duty checks and what each role can do
- [Firearms and licences](./firearms-and-licences.md) - weapon licence range, shop hook, firearm registry, records clerk
- [Events](./events.md) - net events, local events, callbacks and events used from other resources
- [Database](./database.md) - tables, columns and external tables read
- [Troubleshooting](./troubleshooting.md) - known caveats, dead options and common problems

The resource exposes no exports and defines no ACE permissions.
