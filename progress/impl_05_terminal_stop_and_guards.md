# Implementation progress — 05_terminal_stop_and_guards

Status: **COMPLETE — implemented, deployed to BlueSky, all tests green. Awaiting reviewer.**
Date: 2026-06-14

Prior run correctly stopped at a blocker (terminal values absent from the
`Status__c` restricted picklist). Human decision 2026-06-13 added R8 (ADD the 4
terminal values to `Status__c`; KEEP `Sequence_Terminal_Status__mdt` unchanged).
This run resumed from that decision and completed the feature.

## STEP 1 — picklist prerequisite (R8): picklist change + deploy result

- Edited `force-app/main/default/objects/Target__c/fields/Status__c.field-meta.xml`:
  added four values to the restricted `<valueSetDefinition>` —
  `Converted`, `Meeting Booked`, `Do Not Contact`, `Replied` — each matching the
  `Sequence_Terminal_Status__mdt` `Status_Value__c` exactly. All ten existing
  values (Not Cleared … Closed) unchanged; default (`Not Cleared`) unchanged;
  `<restricted>true</restricted>` unchanged.
- Deployed just that field to BlueSky:
  `sf project deploy start --source-dir .../Status__c.field-meta.xml --target-org BlueSky`
  → **Succeeded, 0 component errors** (deploy id 0AfV900000CSlhpKAD).
  (Note: `--metadata Target__c.Status__c` was rejected by this CLI version's
  arg parsing under the cmd wrapper; source-dir deploy of the same component
  succeeded.)
- Reachability verified via anonymous Apex on BlueSky: inserting a Target then
  `update` with `Status__c = 'Converted'` returned `R8_OK` (no
  `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`). Temp script created under
  `scripts/` and deleted.

## STEP 2 — feature implementation (one trigger, extended)

Files modified:
- `force-app/main/default/triggers/TargetTrigger.trigger` — added `before update`
  to the existing trigger; routes by `Trigger.operationType` (`AFTER_INSERT` →
  03 start; `BEFORE_UPDATE` → `TargetTriggerHandler.beforeUpdate`). Trigger stays
  logic-free. **No second trigger created.**
- `force-app/main/default/classes/TargetTriggerHandler.cls` — added:
  - `beforeUpdate(List<Target__c> newList, Map<Id,Target__c> oldMap)` branch.
  - On a record whose `Status__c` CHANGED to a terminal value AND
    `Sequence_Active__c == true`: stamps on `Trigger.new` (NO DML)
    `Sequence_Active__c=false`, `Sequence_Stop_Reason__c =` matching
    `Stop_Reason__c`, `Next_Action_Date__c=null` (R1).
  - Skips when status unchanged (R3), already inactive (R4), or non-terminal.
  - Cached `Map<String,String>` from `Sequence_Terminal_Status__mdt.getAll()`
    (`Status_Value__c` → `Stop_Reason__c`), built once per transaction, no SOQL (R5).
  - New static `Set<Id> processedTerminalStopIds` recursion guard, same Set<Id>
    pattern as feature 03's `processedInsertIds` (R7). 200-safe, pure in-memory.

## STEP 3 — tests

Extended `force-app/main/default/classes/TargetTriggerHandlerTest.cls` (kept all
feature-03 tests; they remain green). Added:
- `testEachTerminalStatusStopsActiveTarget` — each of the 4 terminal statuses on
  an active target → inactive + correct Stop_Reason + null Next_Action_Date, in
  before-update with **no DML beyond a normal update** (measured against a
  non-terminal baseline update; the stamp adds zero DML) (R1, R2, R8).
- `testUnchangedStatusNoStop` — status unchanged → no stop (R3).
- `testAlreadyInactiveNoStop` — already inactive + terminal status → no change (R4).
- `testNonTerminalStatusChangeNoStop` — non-terminal change → no stop.
- `testKillSwitchAutoTerminalStopsScheduler` — deactivated via terminal status →
  `SequenceSchedulerBatch` does not advance step, sends no email, creates no Call
  task (R6).
- `testKillSwitchManualUncheckStopsScheduler` — manual `Sequence_Active__c`
  uncheck → scheduler advances nothing, sends nothing (R6).
- `testBulk200TerminalStop` — 200-record terminal update → all 200 inactive with
  correct reason + null date; stamp adds no DML beyond a non-terminal baseline
  bulk update (R7).
- `testBeforeUpdateGuardInputsNoOp` — null/empty list and null oldMap are no-ops.

### Note on the DML assertion
A record-triggered Flow on `Target__c` in BlueSky performs its own follow-up DML
on update, so a raw "exactly 1 DML" assertion is not valid in this org. The tests
instead prove R2/R7 by comparing the terminal-update DML count to a baseline
non-terminal update on an identical record: the before-update stamp adds **zero**
DML beyond what any Target update already costs (it mutates `Trigger.new` only).

## Requirement traceability (R1–R8)

- **R1** → `testEachTerminalStatusStopsActiveTarget`, `testBulk200TerminalStop`
  (sets inactive + stop reason + null date on terminal change of an active target).
- **R2** → `TargetTrigger` `BEFORE_UPDATE` route + `testEachTerminalStatusStopsActiveTarget`
  (no added DML for the stamp; implemented as a branch of the existing trigger/handler).
- **R3** → `testUnchangedStatusNoStop`.
- **R4** → `testAlreadyInactiveNoStop`.
- **R5** → `getStopReasonByStatus()` reads `Sequence_Terminal_Status__mdt.getAll()`,
  cached, no code change to add/remove a terminal status; exercised by every
  terminal-stop test (correct reasons resolve from CMDT).
- **R6** → `testKillSwitchAutoTerminalStopsScheduler`, `testKillSwitchManualUncheckStopsScheduler`.
- **R7** → `processedTerminalStopIds` Set<Id> guard + `testBulk200TerminalStop`
  (200-record, no extra DML, no governor errors).
- **R8** → `Status__c.field-meta.xml` now contains the 4 terminal values; deployed;
  reachability confirmed; the terminal-stop tests set those values successfully
  (no restricted-picklist error).

## One-trigger-per-object confirmation

- Repo: ripgrep `trigger \w+ on Target__c` → exactly one match,
  `force-app/main/default/triggers/TargetTrigger.trigger` (after insert, before update).
- Org (BlueSky): `SELECT Name FROM ApexTrigger WHERE TableEnumOrId='Target__c'`
  → **1 row, `TargetTrigger`**.

## Test results + coverage (BlueSky)

`sf apex run test --tests TargetTriggerHandlerTest --tests SequenceSchedulerBatchTest --code-coverage`:
- **Outcome: Passed — 26/26 tests pass, 0 failures.**
- Per-feature-class coverage:
  - `TargetTriggerHandler`: **98%**
  - `TargetTrigger`: **100%**
  - `SequenceSchedulerBatch`: 98% (unchanged from 04; exercised by the kill-switch tests)
- Org-wide coverage ~54% (inflated downward by out-of-scope sample classes; per
  ENV NOTES, report per-feature-class coverage — all >= 85%).

## Cleanup

- All temp scripts (`scripts/verify_reachable.apex`, `scripts/test_out.json`,
  `scripts/dep.json`, `scripts/q_trig.soql`, `scripts/trig_out.json`) deleted.
- Only the pre-existing feature-04 `scripts/apex/schedule_sequence_scheduler.apex`
  remains under `scripts/`.
- No `System.debug()` left in committed Apex; no dead code or TODOs.

## tasks.md

All checkboxes marked `[x]`.
