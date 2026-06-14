# Tasks — 03_event_entry_points

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [x] Create `TargetTrigger` (after insert) delegating to `TargetTriggerHandler`, no logic in trigger (R3)
- [x] Implement `TargetTriggerHandler.afterInsert` → enqueue `SequenceStartQueueable` with new Ids (R1)
- [x] Build `SequenceStartQueueable`: re-query targets, call engine `processSteps(stepToSend=1)` for active ones (R2)
- [x] Create `TaskTrigger` (after update) delegating to `TaskTriggerHandler`; reuse existing Task trigger if present (R9)
- [x] Implement `TaskTriggerHandler.afterUpdate`: filter completed sequence calls, set `Next_Action_Date__c = now + Days_Until_Next_Email__c` on matching active targets (R4)
- [x] Exclude non-sequence tasks and inactive/step-mismatch targets (R5, R6)
- [x] Add static `Set<Id>` recursion guards in both handlers (R7)
- [x] Bulkify: one query for related targets, one DML per handler (R8)
- [x] Stall behavior decided: **leave paused** (no fallback timer) — `CallCompleted` steps wait on the rep completing the call
- [x] Write `TargetTriggerHandlerTest`: active insert → step-1 artifacts; inactive insert → nothing (R1, R2)
- [x] Write `TaskTriggerHandlerTest`: matching call complete → date set; non-sequence / inactive / step-mismatch → unchanged (R4, R5, R6)
- [x] Write 200-record bulk tests for insert and task completion (R8)
- [x] Run tests; confirm **>= 85%** coverage; deploy-validate

## Verification

- **R1/R2:** insert active `Target__c` with `Primary_Contact__c`; after `Test.stopTest`
  assert Email 1 (test context), open `Call 1`, completed Email task, `Sequence_Step__c=1`.
- **R4:** set the `Call 1` task `Status='Completed'` → `Next_Action_Date__c` ≈ now +
  `Days_Until_Next_Email__c`; assert **no** new email yet.
- **R5:** complete a `Task` with `Is_Sequence_Call__c=false` → target unchanged.
- **R6:** inactive target's call completed → `Next_Action_Date__c` unchanged.
- **One-trigger-per-object:** confirm only one `TargetTrigger` and one `TaskTrigger` exist.

> Coverage target: **>= 85%** for handlers + queueable.
