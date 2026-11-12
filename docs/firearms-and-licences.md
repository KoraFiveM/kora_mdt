---
title: Firearms and licences
sidebar_position: 9
---

# Firearms and licences

This resource owns the weapon licence test, the licence-only gun shop rule and the firearm registry at Ammu-Nation.

## Weapon licence range

1. At the counter (a sphere target from `interactionPoint`, option "start weapon licence range", or the whole polygon if `interactionPoint` is nil) the client triggers `kora_mdt:server:startWeaponLicence` (1 request per 2 seconds).
2. The server rejects the start if a session is already running, the player is not within `interactionDistance` of the range polygon (polygon plus that padding), the character is unknown, or the player already holds a weapon licence.
3. The server calls `exports.kora_inventory:StartTrainingWeapon(src, weapon, shots)`. On success it records the session and tells the client to spawn one target prop per `targetOffsets` entry. If no target can be created the client cancels the session.
4. Each fired training round arrives as `kora_inventory:server:trainingRoundFired`. A round is counted only if it is owned by this resource, uses the configured weapon, is the next shot in sequence, and the player is still eligible (before the timeout, same character, same routing bucket, inside the zone).
5. When the last round is counted the licence is issued immediately. See [Troubleshooting](./troubleshooting.md): the qualification minigame configured under `qualification` is not part of this flow.
6. The session fails and the training weapon is stopped when the timeout elapses, the player leaves the polygon (client zone exit, plus a check 500 ms after start), the client cancels, or the player disconnects. A failure notice includes the number of rounds fired.

### Issuing the licence

The server writes `kora_mdt_licences` (type `weapon`, number `WPN-` plus the last 6 characters of the citizen ID in upper case plus 4 random digits) and sets `licences.weapon = true` in the player metadata through `exports.kora_core:setMetaData`. A licence counts as held only when both the metadata flag and the table row exist.

## Shop rule and registry

- A `buyItem` hook registered with `exports.kora_inventory:RegisterHook` applies to the shop `Config.mdt.firearms.shopId`. For shared weapon items it rejects any purchase count other than 1 and rejects players without a licence ("You need a weapon licence to purchase firearms."). Other items and shops are untouched.
- On `kora_inventory:server:itemPurchased` for the same shop and a weapon item, the server writes `kora_mdt_firearms` with the serial from the item metadata, the weapon name, the buyer, their licence number and the shop. The row is keyed by serial; a repeat updates owner and licence number. Transfers between players are not registered.

## Looking up a firearm

`kora_mdt:server:shopFirearm` returns serial, weapon name, owner citizen ID, licence number and purchase time.

- `lookupMode = 'npc'`: allowed only within 2.0 units of an entry in `shopRecords`. No job is required. The client spawns an invincible `s_m_m_ammucountry` ped for each entry with a `kora_target` option using the entry label; selecting it asks for a serial and shows weapon and owner as a notification.
- `lookupMode = 'mdt'`: allowed for the police domain (police and judge) anywhere.

The terminal's Firearm registry action always calls the same callback, so in `npc` mode a police officer gets "speak to the store records clerk" unless standing at a clerk. The clerk ped is also spawned in `mdt` mode.
