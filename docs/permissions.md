---
title: Permissions
sidebar_position: 8
---

# Permissions

The resource uses job based roles from `kora_core` and no ACE permissions. The role is computed on the server for every callback and event from `exports.kora_core:getJob`.

## Role resolution

1. If `Config.mdt.roles.requireOnDuty` is true and the job is not on duty, there is no role.
2. A job listed in `judgeJobs` is `judge`, else in `policeJobs` is `police`, else in `medicalJobs` is `medical`, else no role.

A judge passes every domain check, so judges can do everything police and medical can. There are no separate judge-only actions in the code.

## What each role can do

| Capability | Police | Medical | Judge |
| --- | --- | --- | --- |
| Open the terminal | yes | yes | yes |
| Search citizens, open a profile (identity) | yes | yes | yes |
| Profile: firearms, criminal record, reports, warrants, BOLOs | yes | no | yes |
| Profile: medical records | no | yes | yes |
| Dashboard, vehicles, penal code, firearm registry | yes | no | yes |
| Reports, cases, warrants, BOLOs (view and change) | yes | no | yes |
| Add criminal record, analyse casing | yes | no | yes |
| Add medical record | no | yes | yes |
| Charge management | police boss | no | no |

Charge management needs a job in `policeJobs`, on duty if required, with `isboss` on the job or on `job.grade`. The Charges tab is shown only to the `police` role in the client, and the server checks the same boss condition.

## Other access rules

- Firearm serial lookup in `npc` mode needs no role, only being within 2.0 units of a configured clerk. In `mdt` mode it needs the police domain.
- The weapon licence range needs no role; it only needs the player to be at the range. See [Firearms and licences](./firearms-and-licences.md).
- Server events registered through `Kora.events.register` are rate limited, see [Events](./events.md).
