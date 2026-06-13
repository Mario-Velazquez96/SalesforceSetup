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
  (R2, R8 — runs as a Batch `start()` QueryLocator, which does not require the filter to be selective).
- `execute(bc, scope)` → group/iterate and call the engine's **bulk** `processSteps` with
  `stepToSend = Sequence_Step__c + 1` per target (R3). One email send / Task insert /
  Target update per execute (R6). Engine's guard re-checks `Sequence_Active__c` (R5).
- `Database.Stateful` to accumulate counts/errors for the `finish` summary (R1).
- `finish(bc)` → optional admin summary email on errors (per apex-patterns batch finish).

## Schedulable (R4)

- `SequenceSchedulerSchedulable.execute(sc)` → `Database.executeBatch(new
  SequenceSchedulerBatch(), 200)`.
- Provide a one-line scheduling helper (anonymous Apex / setup) using CRON
  **`0 0 0,8,16 * * ?`** (runs at 00:00, 08:00, 16:00 — every 8 hours). The hours list
  (`0,8,16`) is the supported way to express "every 8 hours" in the Apex scheduler;
  alternatively, schedule three `System.schedule` jobs at those hours.
- **8-hourly does NOT increase email volume:** `processStep` advances the step and sets a
  **future** `Next_Action_Date__c`, so an already-processed target is not re-selected later
  the same day (its due date now lies ahead). The daily Apex single-email cap math is
  therefore unchanged by the run frequency — only the latency from "due" to "picked up"
  shrinks from ~1 day to ~8 hours.

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
- **No custom index required:** `start()` returns a `Database.QueryLocator`, which is exempt
  from the "non-selective query against a large object" exception, so the query on
  `Next_Action_Date__c` + `Sequence_Active__c` runs without a custom index. Performance is
  acceptable at the org's expected (modest) `Target__c` volume. (Dropped 2026-06-13; was the
  feature 01 former R15 index dependency.)
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

- **Schedule = every 8 hours** `0 0 0,8,16 * * ?` (revised 2026-06-13, supersedes the prior
  2026-06-12 daily `0 0 6 * * ?` decision). `Next_Action_Date__c` remains a `DateTime`; a
  due target is realized on the first scheduled run on/after the due DateTime, now within
  ~8 hours. Wait granularity is no longer "one day."
- **Custom index dropped** (2026-06-13) — the batch `start()` QueryLocator is exempt from the
  non-selective-query limit and volume is modest, so the former `Next_Action_Date__c` custom
  index (feature 01 former R15) is no longer a prerequisite.
- **Email cap** — volume confirmed under 5,000/day; monitor in production, no throttling now.
- **No fallback timer** — call-driven stalls remain paused by decision (03), so this batch
  does **not** pick up stalled call-driven steps; it only processes targets with a populated
  due `Next_Action_Date__c`.
