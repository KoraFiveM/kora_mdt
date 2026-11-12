---
title: "Commands"
sidebar_position: 4
---


# Commands

Kora MDT adds one player-facing command, registered client-side and backed entirely by server checks.

## Built-in commands

### `/mdt`

Requests the terminal be opened. The client only triggers `kora_mdt:server:open`; the server re-checks the caller’s role and duty status before anything opens, and shows a notification instead when the check fails.

| Field | Details |
| --- | --- |
| Context | In-game · client command (name configurable via `Config.mdt.command`) |
| Arguments | No arguments. |
| Access | Must resolve to the police, medical or judge role under `Config.mdt.roles` (and be on duty, when `requireOnDuty` is true). |

**Example**

```text
/mdt
```

**Result**

Opens the Mobile Data Terminal (or Medical Records Terminal for a medical-only role) with tabs matching the caller’s role, or shows "You must be on duty as police, EMS, or a judge to use the MDT."

## No standalone exports

Kora MDT does not declare any `exports` of its own in `fxmanifest.lua`, and no other resource in this recipe calls `exports.kora_mdt` / `exports.kora_mdt`. Everything is reached through the command, the net/local events named above, and the `kora_mdt:server:*` callbacks documented in How to use.

## Behaviour details

| Command | Behaviour |
| --- | --- |
| `/mdt` (name set by `Config.mdt.command`) | Registered on the client without command restriction. It asks the server to open the terminal; the server replies with an error notification unless the player holds a configured job (and is on duty when `requireOnDuty` is true). Rate limit: 4 requests per 2 seconds. |

The resource defines no ACE permissions. See [Permissions](./permissions.md) for roles and [Configuration](./configuration.md) for `Config.mdt.command`.
