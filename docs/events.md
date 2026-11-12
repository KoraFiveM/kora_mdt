---
title: Events
sidebar_position: 10
---

# Events

The resource exports nothing. Its events and callbacks are internal to the terminal; other resources should not trigger them.

## Server events (client to server)

Registered with `Kora.events.register` and rate limited (`max` per `window` ms).

| Event | Payload | Limit | Behaviour |
| --- | --- | --- | --- |
| `kora_mdt:server:open` | none | 4 / 2000 | Computes the role and triggers `kora_mdt:client:open`, or sends an error notification. |
| `kora_mdt:server:beginAnalysis` | `caseId` string | 2 / 3000 | Starts casing analysis for police or judge holding a matching evidence bag. Silent when refused. |
| `kora_mdt:server:analysisStage` | proof token string | 5 / 5000 | Consumes the stage proof and advances or completes the analysis. |
| `kora_mdt:server:cancelAnalysis` | none | 4 / 3000 | Drops the player's analysis state. |
| `kora_mdt:server:startWeaponLicence` | none | 1 / 2000 | Starts a licence range session. |
| `kora_mdt:server:completeWeaponLicence` | proof token string | 3 / 5000 | Requires a pending qualification authorisation, which this resource never creates (see [Troubleshooting](./troubleshooting.md)). |
| `kora_mdt:server:cancelWeaponLicence` | none | 3 / 5000 | Ends the player's session as failed. |

## Client events (server to client)

| Event | Payload | Behaviour |
| --- | --- | --- |
| `kora_mdt:client:open` | `role`, `isPoliceBoss` | Builds and opens the terminal for `police`, `medical` or `judge`. |
| `kora_mdt:client:analysisStage` | `stage`, `authorization` | Plays the stage minigame and returns the proof. |
| `kora_mdt:client:analysisComplete` | `{ caseId, weaponSerial, weapon }` | Shows the result notice. |
| `kora_mdt:client:weaponLicenceStart` | settings table | Spawns targets and the exit zone. |
| `kora_mdt:client:weaponLicenceQualification` | `authorization` | Plays the qualification minigame (never sent by the current server code). |
| `kora_mdt:client:weaponLicenceResult` | `passed`, `shots` | Clears targets and shows the result notice. |

## Local server event

| Event | Behaviour |
| --- | --- |
| `kora_mdt:server:databaseReady` | Triggered by `server/boot.lua` when the schema is ready. The handler seeds and loads the charge catalogue. Until then callbacks that need it answer "MDT database is still starting". |

## Callbacks (`Kora.callback.register`, server)

All return `nil, error` (or `false, error`) when the caller lacks the role. "Police" means police or judge, "medical" means medical or judge.

| Callback | Role | Returns |
| --- | --- | --- |
| `kora_mdt:server:person` | any | Citizen profile; extra sections by role. |
| `kora_mdt:server:vehicle` | police | Vehicle record with BOLOs. |
| `kora_mdt:server:searchPeople`, `searchVehicles` | any, police | Search rows. |
| `kora_mdt:server:charges` | police | Active charge catalogue. |
| `kora_mdt:server:canManageCharges` | any | Boolean boss check (not used by the terminal code). |
| `kora_mdt:server:manageCharges`, `createCharge`, `updateCharge` | police boss | Charge administration. |
| `kora_mdt:server:addCriminal` | police | Adds a criminal record. |
| `kora_mdt:server:addMedical` | medical | Adds a medical record. |
| `kora_mdt:server:shopFirearm` | see [Firearms and licences](./firearms-and-licences.md) | Firearm registry row. |
| `kora_mdt:server:dashboard` | police | Counts and recent reports. |
| `kora_mdt:server:reports`, `reportOptions`, `report`, `createReport`, `closeReport` | police | Report list, picker options, detail, create, close. |
| `kora_mdt:server:cases`, `case`, `createCase`, `updateCaseStatus`, `linkCaseReport` | police | Case list, detail, create, status, link a report. |
| `kora_mdt:server:warrants`, `createWarrant`, `closeWarrant` | police | Warrant list, create, serve or revoke. |
| `kora_mdt:server:bolos`, `createBolo`, `resolveBolo` | police | BOLO list, create, resolve. |

## Used from other resources

| Name | Side | Use |
| --- | --- | --- |
| `exports.kora_core:getPlayerData`, `getJob`, `getShared`, `setMetaData` | server | Citizen ID, job and duty, weapon definitions, licence metadata. |
| `exports.kora_inventory:RegisterHook('buyItem', ...)` | server | Licence-only gun shop. |
| `exports.kora_inventory:GetItemsByName`, `StartTrainingWeapon`, `StopTrainingWeapon` | server | Evidence bags and the training weapon. |
| `exports.kora_police:GetBallisticCasing` | server | Casing lookup. |
| `exports.kora_target:addSphereZone`, `addPolyZone`, `addEntity` | client | Interactions. |
| `exports.kora_lib:minigames_play` and `Kora.minigames.authorizeProof`, `consumeProof` | both | Analysis stages. |
| `kora_inventory:server:itemPurchased`, `kora_inventory:server:trainingRoundFired` | server (listened) | Firearm registration and range rounds. |
| `playerDropped` | server (listened) | Ends range sessions and analysis state. |
| `onClientResourceStart`, `onClientResourceStop` for `kora_target` | client (listened) | Re-register or clear target interactions. |
