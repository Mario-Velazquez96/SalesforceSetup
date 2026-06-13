# Design — 04_scheduler_batch

**Source:** Target_Sequence_Solution_Design.md §2 (Features 7–10), §4.2, §6, §10

## Approach

A `Database.Batchable` + `Schedulable` pair. The batch is a thin driver over the engine
(02): it selects due targets and calls `processStep(target, step+1)` for each. All the
sending, task creation, and next scheduling stay in the engine, so the batch carries no
cadence rules — it only answers "who is due now?".

## Class layout

```
classes/
  SequenceSchedulerBatch.cls        // Batchable<sObject> + Stateful
  SequenceSchedulerSchedulable.cls  // Schedulable → executeBatch(scope 200)
```

## Batch logic (R1–R3, R6)

- `start(bc)` → `Database.getQueryLocator` via `TargetSelector.getDueForScheduler(now)`:
  `SELECT Id, Sequence_Step__c, Sequence_Active__c, Primary_Contact__c, Days_Until_Next_Email__c, Sequence_Attachment_Id__c, Next_Action_Date__c FROM Target__c WHERE Sequence_Active__c = true AND Next_Action_Date__c <= :now AND Sequence_Step__c < 10 WITH USER_MODE`
  (R2, R8 — selective on indexed `Next_Action_Date__c`).
- `execute(bc, scope)` → group/iterate and call the engine's **bulk** `processSteps` with
  `stepToSend = Sequence_Step__c + 1` per target (R3). One email send / Task insert /
  Target update per execute (R6). Engine's guard re-checks `Sequence_Active__c` (R5).
- `Database.Stateful` to accumulate counts/errors for the `finish` summary (R1).
- `finish(bc)` → optional admin summary email on errors (per apex-patterns batch finish).

## Schedulable (R4)

- `SequenceSchedulerSchedulable.execute(sc)` → `Database.executeBatch(new
  SequenceSchedulerBatch(), 200)`.
- Provide a one-line scheduling helper (anonymous Apex / setup) using CRON **`0 0 6 * * ?`
  (daily 06:00)** — confirmed frequency.

## Why one batch covers Features 2–10 (§4.2, §6)

- Steps 2–6 (call-driven): `03` sets `Next_Action_Date__c = now + Days_Until_Next_Email__c`
  on call completion → the batch picks them up after the wait.
- Steps 7–10 (timer): the engine set `Next_Action_Date__c = now + Next_Wait_Days__c`
  (14/7/14/14) when it produced step 6/7/8/9 → the batch picks them up.
- Both paths converge on the same query + `processStep(step+1)`.

## Security (§9)

- Batch runs in system context but the engine enforces USER_MODE DML/SOQL and the
  kill-switch guard. No hardcoded Ids. `inherited sharing`/`with sharing` per the engine.

## Bulkification & scale (R6, R8)

- Scope 200; each `execute` gets fresh limits.
- Selective query on indexed `Next_Action_Date__c` + `Sequence_Active__c` (index from 01)
  to stay performant at LDV (DM2 avoidance).
- Respect the 5,000/day Apex email cap — monitor; throttle scope/frequency if volume grows.

## Test approach (§12 step 3)

- `SequenceSchedulerBatchTest`: seed a target at `Sequence_Step__c=6` with a **past**
  `Next_Action_Date__c`; run the batch in `Test.startTest/stopTest` → assert advance to
  step 7 (Email 7 in test context, `Call 7`, `Next_Action_Date__c ≈ now + 7d`).
- Future-dated target → not selected (assert unchanged).
- Inactive target with a past date → not advanced (R5).
- **Bulk:** 200 due targets → one DML per object, no governor errors.
- Coverage target **>= 85%**.

## Resolved decisions / discrepancies

- **Schedule = daily** `0 0 6 * * ?` (confirmed 2026-06-12). Wait granularity is one day.
- **Email cap** — volume confirmed under 5,000/day; monitor in production, no throttling now.
- **No fallback timer** — call-driven stalls remain paused by decision (03), so this batch
  does **not** pick up stalled call-driven steps; it only processes targets with a populated
  due `Next_Action_Date__c`.
