# Tasks — 05_terminal_stop_and_guards

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [ ] Add `before update` to the **existing** `TargetTrigger` (no second trigger) (R2)
- [ ] Add `beforeUpdate` branch to `TargetTriggerHandler`, routed by `Trigger.operationType` (R2)
- [ ] Read `Sequence_Terminal_Status__mdt.getAll()` into a cached `Map<String,String>` (R5)
- [ ] On terminal status change of an active target, stamp `Sequence_Active__c=false`, `Sequence_Stop_Reason__c`, `Next_Action_Date__c=null` on `Trigger.new` (no DML) (R1)
- [ ] Skip when status unchanged or already inactive (R3, R4)
- [ ] Share the static `Set<Id>` recursion guard with feature 03 (R7)
- [ ] Extend `TargetTriggerHandlerTest`: each terminal status stops + writes reason, no extra DML (R1, R2)
- [ ] Add negative tests: unchanged status, already-inactive, non-terminal status (R3, R4)
- [ ] Add kill-switch tests: auto- and manual-deactivation halt scheduler advancement (R6)
- [ ] Add 200-record bulk update test (R7)
- [ ] Run tests; confirm **>= 85%** coverage; deploy-validate

## Verification

- **R1:** active target, set `Status__c='Converted'` → `Sequence_Active__c=false`,
  `Sequence_Stop_Reason__c='Converted'`, `Next_Action_Date__c=null`; assert no added DML
  for the stamp (before-save).
- **R3/R4:** update with unchanged status, or update an already-inactive target → no change.
- **R6 (§12 steps 5–6):** deactivate mid-cadence (auto via terminal status and via manual
  uncheck), run `SequenceSchedulerBatch` → no email sent, `Sequence_Step__c` unchanged.
- **One-trigger-per-object:** confirm still a single `TargetTrigger` with insert + update
  branches.

> Coverage target: **>= 85%** for the `TargetTriggerHandler` (combined with 03).
