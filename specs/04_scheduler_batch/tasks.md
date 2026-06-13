# Tasks — 04_scheduler_batch

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [ ] Build `SequenceSchedulerBatch` implementing `Database.Batchable<sObject>` + `Database.Stateful` (R1)
- [ ] Implement `start` → selective `QueryLocator`: active, `Next_Action_Date__c <= now`, `Sequence_Step__c < 10`, USER_MODE (R2, R8)
- [ ] Implement `execute` → engine `processSteps(step+1)`, one DML per object (R3, R6)
- [ ] Rely on the engine kill-switch guard for targets deactivated mid-run (R5)
- [ ] Implement `finish` → stateful counts + optional admin error summary (R1)
- [ ] Build `SequenceSchedulerSchedulable` → `executeBatch(scope 200)` (R4)
- [ ] Provide CRON scheduling helper/instructions — **daily `0 0 6 * * ?`** (confirmed) (R4)
- [x] Decided: **daily** schedule; email volume confirmed **under** the 5,000/day cap (open items resolved)
- [ ] Write `SequenceSchedulerBatchTest`: step 6 + past date → advance to 7; future date → unchanged; inactive → unchanged (R2, R3, R5)
- [ ] Write the 6→10 walk test (run batch ×4) verifying 14/7/14/14 (R3)
- [ ] Write 200-record bulk test: one DML per object, no governor errors (R6)
- [ ] Run tests; confirm **>= 85%** coverage; deploy-validate

## Verification

- **R2/R3:** target `Sequence_Step__c=6`, `Next_Action_Date__c = now-1h` → run batch →
  step 7, `Call 7`, `Next_Action_Date__c ≈ now + 7d`.
- **Cadence walk (§12 step 3):** repeat the batch four times → 6→7→8→9→10 with waits
  14/7/14/14; step 10 leaves `Next_Action_Date__c` null and is no longer selected.
- **R5:** inactive target with past date → not advanced.
- Future-dated target → not selected.

> Coverage target: **>= 85%** for batch + schedulable.
