# Review — 04_scheduler_batch

**Verdict: APPROVE**
**Date:** 2026-06-14
**Reviewer:** reviewer subagent

The feature meets every requirement, all 11 tests pass, per-class coverage is
well above the 85% gate, and scope is clean. The leader may mark
`04_scheduler_batch` as `done`.

## 1. Requirement -> test traceability (R1–R8)

| Req | Verified | Evidence |
| --- | --- | --- |
| R1 | YES | `SequenceSchedulerBatch implements Database.Batchable<sObject>, Database.Stateful`; stateful `totalProcessed`/`totalErrors`/`errorMessages` + `finish` summary. Covered by `testFinishSendsSummaryOnError`, `testFinishNoEmailOnCleanRun`. |
| R2 | YES | `start()` returns a `Database.QueryLocator`: `Sequence_Active__c = true AND Next_Action_Date__c <= :now AND Sequence_Step__c < 10 WITH USER_MODE` (also `!= null`). Asserted by `testDueStep6AdvancesToStep7` (selected), `testFutureDatedTargetNotSelected` (not selected), and the walk's step-10 de-selection check. |
| R3 | YES | `execute` builds one `StepRequest(t, step+1)` per target and calls `SequenceEngineService.processSteps`. `testDueStep6AdvancesToStep7` asserts 6->7, `Call 7` task, Next_Action_Date ~ now+7d; `testWalkSixToTen` walks 6->10. |
| R4 | YES | `SequenceSchedulerSchedulable implements Schedulable`, `execute` -> `Database.executeBatch(new SequenceSchedulerBatch(), 200)` (SCOPE=200). `testSchedulableEnqueuesBatch` asserts `CronExpression = 0 0 0,8,16 * * ?` (every 8 hours). |
| R5 | YES | Engine kill-switch reused (not reimplemented). `testInactiveTargetNotAdvanced`: inactive target with past date stays at step 6, no tasks. |
| R6 | YES | `testBulk200OneDmlPerObject`: 200-record scope, exactly 2 DML (Task insert + Target update), all 200 advanced; scope asserted = 200. |
| R7 | YES (operational) | Resolved decision — volume confirmed under the 5,000/day cap; advanced targets carry a future Next_Action_Date so no same-day re-send. Documented; monitored in production. |
| R8 | YES | `start()` uses `Database.getQueryLocator` (Batch QueryLocator, exempt from the selective-query rule). No custom-index dependency in code or class header. |

### Acceptance cadence walk
`testWalkSixToTen` drives start/execute/finish once per step (re-due-ing
between runs to simulate the next scheduled run):
- 6 -> 7, Next_Action_Date ~ now+7d
- 7 -> 8, ~ now+14d
- 8 -> 9, ~ now+14d
- 9 -> 10, Next_Action_Date = null
- Step-10 target is NOT returned by a fresh `start()` (step < 10 fails) even
  with a past date.

The destination-step waits realize as 7/14/14/null for steps 7/8/9/10 — the
engine sets the DESTINATION step's wait, which matches the spec's per-step
config and the "14/7/14/14" cadence label (implementer flagged this naming
nuance honestly). Future-dated target not selected: `testFutureDatedTargetNotSelected`.
Inactive not advanced: `testInactiveTargetNotAdvanced`.

## 2. R1/R4 structure
- `SequenceSchedulerBatch`: Batchable + Stateful with start/execute/finish. Confirmed.
- `SequenceSchedulerSchedulable`: Schedulable, executeBatch scope 200. Confirmed.
- CRON helper documents EVERY 8 HOURS `0 0 0,8,16 * * ?` in the class header,
  `scripts/apex/schedule_sequence_scheduler.apex`, and the test constant
  `CRON_8H`. No daily-only (`0 0 6 * * ?`) assumption remains in the feature's
  code, tests, spec, or design.

## 3. R8 / index
- `start()` is a Batch `Database.getQueryLocator` — no custom index dependency.
- No custom-index metadata was created or reintroduced by this feature; no
  `<index>` element exists in any object metadata.

## 4. Test run (executed by reviewer)
Command: `sf apex run test --target-org BlueSky --test-level RunSpecifiedTests
--tests SequenceSchedulerBatchTest --code-coverage --json --wait 30`
- Outcome: **Passed — 11 / 11, 0 failing.**
- Per-class coverage (parsed from the JSON coverage block):
  - `SequenceSchedulerBatch` — **96%** (49/51)
  - `SequenceSchedulerSchedulable` — **100%** (3/3)
- Both exceed the >= 85% per-feature-class gate. (Org-wide 52% is pre-existing
  out-of-scope sample classes — judged per feature class per instructions.)

## 5. Conventions & scope discipline
- No SOQL/DML inside loops in the new classes. The only `for` in `execute`
  builds a `StepRequest` list; the single engine call does one DML per object.
- `WITH USER_MODE` on the start query.
- Scope 200 (constant), never exceeded.
- Engine reused via `SequenceEngineService.processSteps` (StepRequest signature
  matches) — not duplicated.
- No `System.debug()` in the new classes. No hardcoded Ids (admin recipient
  resolved at runtime).
- `tasks.md` fully `[x]` (all 12 items).
- Repo clean: working tree adds only the 3 classes + meta, the operational
  helper under `scripts/apex/`, the manifest update, and the impl report.
  No scratch JSON/log/diagnostic files left behind.
- `manifest/package.xml` adds exactly the 3 ApexClass members (no extra/out-of-
  scope metadata).

## Non-blocking observation (NOT a reject reason)
The feature-01 field `Target__c/Next_Action_Date__c.field-meta.xml` still has a
stale **description** string: "Indexed for the selective batch query. (R5, R15)".
This is documentation drift from the 2026-06-13 index-drop decision and lives in
feature 01's metadata, not in anything this feature created or changed. It is
out of scope for 04 and does not affect correctness. Recommend the leader queue
a one-line description cleanup against feature 01 separately.

## Conclusion
APPROVE. The feature may be marked `done`.
