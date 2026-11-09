# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_mdt — Police & EMS

  @kora_mdt @checklist @checklist:kora_mdt:open-mdt-command @cat:police-and-ems
  Scenario: Open MDT with /mdt
    """
    Checklist test: As on-duty police/EMS/judge run /mdt; terminal opens. Off-duty or other jobs are refused with an error.
    """
    Given my job is "police"
    And I am on duty
    When I run the command "/mdt"
    Then the "qbmdt:terminal" app should be open
    When I manually: set myself off duty or switch to a job that is not police, EMS or judge
    And I run the command "/mdt"
    Then I should see a notification containing "You must be on duty as police, EMS, or a judge to use the MDT."
    And I should see an error notification

  @kora_mdt @checklist @checklist:kora_mdt:dashboard @cat:police-and-ems
  Scenario: Operations dashboard counts
    """
    Checklist test: Police: open Dashboard tab; shows open reports, cases, warrants and BOLO counts and recent items.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Dashboard tab
    Then I confirm: the dashboard shows open report, case, warrant and BOLO counts
    And I confirm: recent items are listed

  @kora_mdt @checklist @checklist:kora_mdt:citizen-search @cat:police-and-ems
  Scenario: Search citizens by name/CID/phone
    """
    Checklist test: Search tab > Search citizens; type 2+ chars of name, citizen ID or phone; results limited to 25; pick a row to open profile.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Search tab and choose Search citizens
    And I manually: type 2 or more characters of a citizen name, citizen ID or phone number
    Then I confirm: matching citizens are listed with at most 25 results
    When I manually: pick a result row
    Then I confirm: the citizen profile opens

  @kora_mdt @checklist @checklist:kora_mdt:citizen-profile @cat:police-and-ems
  Scenario: Citizen profile details
    """
    Checklist test: Open a citizen: identity, licences, firearms, reports, warrants, BOLOs, criminal history; medical history only for medical roles.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: search for a citizen and open their profile
    Then I confirm: the profile shows identity, licences, firearms, reports, warrants, BOLOs and criminal history
    And I confirm: medical history is not shown to a police-only role
    When I manually: switch to an on-duty ambulance job, reopen the MDT and open the same profile
    Then I confirm: medical history is shown for the medical role

  @kora_mdt @checklist @checklist:kora_mdt:vehicle-search @cat:police-and-ems
  Scenario: Search vehicles and view record
    """
    Checklist test: Search tab > Search vehicles by plate/model/owner/CID; record shows owner, state, garage/impound lot, active BOLOs.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Search tab and choose Search vehicles
    And I manually: search by plate, model, owner or citizen ID and open a result
    Then I confirm: the record shows owner, state, garage or impound lot and active BOLOs

  @kora_mdt @checklist @checklist:kora_mdt:penal-code @cat:police-and-ems
  Scenario: Penal code list
    """
    Checklist test: Search tab > Penal code; lists charge codes with fines (SPD-01, WPN-01, WPN-02, VEH-01).
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Search tab and choose Penal code
    Then I confirm: the list shows SPD-01, WPN-01, WPN-02 and VEH-01 with their fines

  @kora_mdt @checklist @checklist:kora_mdt:firearm-registry @cat:police-and-ems
  Scenario: Firearm registry lookup
    """
    Checklist test: Search tab > Firearm registry; enter a gun serial; shows weapon and owner citizen ID if registered.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Search tab and choose Firearm registry (only applies when Config.mdt.firearms.lookupMode is mdt)
    And I manually: enter a registered gun serial
    Then I confirm: the weapon and owner citizen ID are shown if registered (only applies when lookupMode is mdt; otherwise mark Pass if the lookup is only at the clerk)

  @kora_mdt @checklist @checklist:kora_mdt:create-report @cat:police-and-ems
  Scenario: Create incident report
    """
    Checklist test: Reports tab > New incident report; title + narrative required, subject (CID or exact name) and charge optional; saved and listed.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Reports tab and choose New incident report
    And I manually: fill in a title and narrative, optionally a subject and charge, and save
    Then I confirm: the report is saved and appears in the list

  @kora_mdt @checklist @checklist:kora_mdt:report-validation @cat:police-and-ems
  Scenario: Report required-field validation
    """
    Checklist test: Submit report with empty narrative or a mistyped citizen ID; server returns an error naming the missing/invalid field.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Reports tab and submit a new report with an empty narrative
    Then I confirm: an error names the missing narrative field
    When I manually: submit a report with a mistyped citizen ID containing a digit
    Then I confirm: an error says the citizen was not found or is invalid

  @kora_mdt @checklist @checklist:kora_mdt:view-close-report @cat:police-and-ems
  Scenario: View and close a report
    """
    Checklist test: Reports tab: select a row to view details; use Close report (confirm) and confirm status changes to closed.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Reports tab and select a report row
    Then I confirm: the report details are shown
    When I manually: use Close report and confirm
    Then I confirm: the report status changes to closed

  @kora_mdt @checklist @checklist:kora_mdt:open-case @cat:police-and-ems
  Scenario: Open an investigation case
    """
    Checklist test: Cases tab > Open a case with title, priority (low/normal/high/critical) and summary; appears in list.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Cases tab and choose Open a case
    And I manually: enter a title, choose a priority (low, normal, high or critical), enter a summary and save
    Then I confirm: the case appears in the list

  @kora_mdt @checklist @checklist:kora_mdt:attach-report-to-case @cat:police-and-ems
  Scenario: Attach report to case
    """
    Checklist test: Cases tab > Attach report to case; pick a case and report; linked report shows in the case timeline.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open the Cases tab and choose Attach report to case
    And I manually: pick a case and a report and confirm
    Then I confirm: the linked report shows in the case timeline

  @kora_mdt @checklist @checklist:kora_mdt:case-status @cat:police-and-ems
  Scenario: Case begin investigation / close / reopen
    """
    Checklist test: Open a case record and use Begin investigation, Close case, Reopen case actions; status updates.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT terminal (the mdt command)
    Then the "qbmdt:terminal" app should be open
    When I manually: open a case record and use Begin investigation
    Then I confirm: the case status updates to investigating
    When I manually: use Close case
    Then I confirm: the case status updates to closed
    When I manually: use Reopen case
    Then I confirm: the case status updates to reopened

  @kora_mdt @checklist @checklist:kora_mdt:issue-warrant @cat:police-and-ems @manual
  Scenario: Issue warrant (judge)
    """
    Checklist test: Warrants tab > Issue warrant with citizen ID, reason, days (max 30); warrant appears on that citizen's profile.
    """
    When I manually: open the MDT as a judge and go to the Warrants tab
    And I manually: choose Issue warrant and enter a citizen ID, a reason and a number of days up to 30
    And I manually: submit the warrant
    Then I confirm: the warrant is saved
    When I manually: open that citizen's profile in the MDT
    Then I confirm: the new warrant appears on that citizen's profile

  @kora_mdt @checklist @checklist:kora_mdt:close-warrant @cat:police-and-ems
  Scenario: Serve or revoke a warrant
    """
    Checklist test: Open a warrant row and serve/revoke it; status changes and it disappears from active alerts.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT and go to the Warrants tab
    And I manually: open an active warrant row and serve or revoke it
    Then I confirm: the warrant status changes to served or revoked
    And I confirm: the warrant no longer appears in the active alerts

  @kora_mdt @checklist @checklist:kora_mdt:create-bolo @cat:police-and-ems
  Scenario: Create person/vehicle BOLO
    """
    Checklist test: BOLOs tab > Create BOLO; choose Person or Vehicle, enter CID/name/plate, title, description, days; shows on profile/vehicle.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT and go to the BOLOs tab
    And I manually: choose Create BOLO and select Person or Vehicle
    And I manually: enter a CID or name or plate, a title, a description and a number of days, then submit
    Then I confirm: the BOLO is created and listed
    And I confirm: the BOLO shows on the citizen profile or the vehicle record

  @kora_mdt @checklist @checklist:kora_mdt:resolve-bolo @cat:police-and-ems
  Scenario: Resolve a BOLO
    """
    Checklist test: Open a BOLO row and resolve it; it no longer appears as active on profile or vehicle record.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT and go to the BOLOs tab
    And I manually: open an active BOLO row and resolve it
    Then I confirm: the BOLO is marked resolved
    And I confirm: it no longer appears as active on the profile or vehicle record

  @kora_mdt @checklist @checklist:kora_mdt:criminal-record @cat:police-and-ems
  Scenario: Add criminal record
    """
    Checklist test: Tools tab > Add criminal record with citizen ID, charge, notes; entry appears in that citizen's criminal history.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT and go to the Tools tab
    And I manually: choose Add criminal record and enter a citizen ID, a charge and notes, then submit
    And I manually: open that citizen's profile in the MDT
    Then I confirm: the entry appears in that citizen's criminal history

  @kora_mdt @checklist @checklist:kora_mdt:medical-record @cat:police-and-ems
  Scenario: Add medical record (EMS)
    """
    Checklist test: As ambulance on duty: Medical records tab > Add medical record with CID and notes; visible in patient profile.
    """
    Given my job is "ambulance"
    And I am on duty
    When I manually: open the MDT and go to the Medical records tab
    And I manually: choose Add medical record and enter a CID and notes, then submit
    And I manually: open that patient's profile in the MDT
    Then I confirm: the medical record is visible in the patient profile

  @kora_mdt @checklist @checklist:kora_mdt:charge-management @cat:police-and-ems
  Scenario: Manage charges (police boss)
    """
    Checklist test: As police boss: Charges tab; create a new charge (code, name, fine) and edit an existing charge's name/fine.
    """
    Given my job is "police"
    And I am on duty
    When I manually: make sure my character has the police boss grade
    And I manually: open the MDT and go to the Charges tab
    And I manually: create a new charge with a code, a name and a fine
    Then I confirm: the new charge appears in the charge list
    When I manually: edit an existing charge's name and fine and save
    Then I confirm: the edited charge shows the new name and fine

  @kora_mdt @checklist @checklist:kora_mdt:ballistic-analysis @cat:police-and-ems
  Scenario: Ballistic casing analysis
    """
    Checklist test: Tools tab > Analyse ballistic casing with a casing case ID; complete skillbar, circuit, pinpad stages; notice links weapon serial.
    """
    Given my job is "police"
    And I am on duty
    When I manually: open the MDT and go to the Tools tab
    And I manually: choose Analyse ballistic casing and enter a casing case ID
    And I manually: complete the skillbar, circuit and pinpad stages
    Then I confirm: a notice links the weapon serial

  @kora_mdt @checklist @checklist:kora_mdt:weapon-licence-range @cat:police-and-ems
  Scenario: Ammu-Nation weapon licence range
    """
    Checklist test: At Ammu-Nation range counter (22.5,-1104.5,29.8) target 'start weapon licence range'; fire 10 rounds at targets, pass skillbar.
    """
    When I manually: go to the Ammu-Nation range counter at 22.5, -1104.5, 29.8
    And I select the "start weapon licence range" target option
    And I manually: fire all 10 rounds at the targets
    And I manually: pass the skillbar
    Then I should see a notification containing "Qualification passed. Weapon licence issued."

  @kora_mdt @checklist @checklist:kora_mdt:weapon-licence-leave-zone @cat:police-and-ems
  Scenario: Range cancels when leaving building
    """
    Checklist test: Start the licence range then walk out of Ammu-Nation; training weapon is removed and session cancelled with a notice.
    """
    When I manually: go to the Ammu-Nation range counter at 22.5, -1104.5, 29.8
    And I select the "start weapon licence range" target option
    And I manually: walk out of the Ammu-Nation building
    Then I should see a notification containing "You left Ammu-Nation. The range weapon was removed."
    And I confirm: the training weapon is removed and the range session is cancelled

  @kora_mdt @checklist @checklist:kora_mdt:firearm-sale-registration @cat:police-and-ems
  Scenario: Firearm sale auto-registered
    """
    Checklist test: Buy a weapon from the Ammu-Nation shop (needs weapon licence); sale is written to the firearm registry with serial.
    """
    Given I have 1 "weaponlicense"
    When I manually: go to the Ammu-Nation shop and buy a weapon
    Then I confirm: the purchase succeeds
    And I confirm: the sale is written to the firearm registry with the weapon serial

  @kora_mdt @checklist @checklist:kora_mdt:records-clerk-npc @cat:police-and-ems
  Scenario: Ammu-Nation records clerk lookup
    """
    Checklist test: At the clerk ped (23.24,-1105.29,29.80) target 'Ammu-Nation records clerk'; enter a gun serial and get weapon + owner.
    """
    When I manually: go to the Ammu-Nation records clerk ped at 23.24, -1105.29, 29.80
    And I select the "Ammu-Nation records clerk" target option
    And I manually: enter a gun serial and submit
    Then I confirm: the weapon and its owner are shown
