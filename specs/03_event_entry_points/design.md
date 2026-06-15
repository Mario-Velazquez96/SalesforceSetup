# Design — 03_event_entry_points

**Source:** Target_Sequence_Solution_Design.md §2, §4.2, §9; slicing-guide (one-trigger-per-object)

## Approach

Thin event capture over the engine from `02`. Two triggers, two handlers, one queueable.
No business logic in triggers. The **start** path is async (Queueable) to keep the insert
transaction lean and isolate the email work (§4.2); the **call-completion** path only sets
a due date — the email itself is sent later by the scheduler (04), which unifies the
4-day call wait with the timer waits.

## Class layout

```
triggers/
  TargetTrigger.trigger     // after insert  (before-update branch added in 05)
  TaskTrigger.trigger       // after update
classes/
  TargetTriggerHandler.cls  // with sharing; afterInsert → enqueue SequenceStartQueueable
  TaskTriggerHandler.cls    // with sharing; afterUpdate → set Next_Action_Date
  SequenceStartQueueable.cls// Queueable; processStep(target, 1) for new active targets
```

## TargetTrigger (after-insert) → Queueable (R1, R2)

- `TargetTrigger` delegates to `TargetTriggerHandler` via `switch on Trigger.operationType`.
- `afterInsert` collects new Ids and enqueues `SequenceStartQueueable` (R1).
- `SequenceStartQueueable.execute` re-queries the targets (USER_MODE, with
  `Sequence_Active__c`, `Primary_Contact__c`, `Sequence_Step__c`) and calls the engine's
  bulk `processSteps` with `stepToSend=1` for active ones (R2). The engine's own guard
  (02/R7) skips inactive targets defensively.

> **One-trigger-per-object:** `05_terminal_stop_and_guards` adds a **before-update** branch
> to *this* `TargetTrigger`/`TargetTriggerHandler`. Do not create a second trigger
> (slicing-guide). Route by `Trigger.operationType` in the handler.

## TaskTrigger (after-update) → set Next_Action_Date (R4–R6, R10)

- `afterUpdate`: filter Tasks where `Status` changed to `Completed` **and**
  `Is_Sequence_Call__c=true` (R5 excludes logged Email activities, which have it false).
- Collect `WhatId` (Target Ids) + each Task's `Sequence_Step__c`; one query via
  `TargetSelector` for those Targets (active, with `Sequence_Step__c`,
  `Days_Until_Next_Email__c`).
- For each candidate, read the matched step's `Sequence_Step_Config__mdt` (via
  `SequenceStepConfigService`, keyed by the Task's `Sequence_Step__c`) and **only** proceed
  when `Next_Trigger_Type__c == 'CallCompleted'`. Timer/None steps are a no-op (R10): the
  engine has already set `Next_Action_Date__c = now + Next_Wait_Days__c` and that timer
  must govern — completing the Call on such a step must not overwrite it.
- For each Target where active (R6), `Sequence_Step__c == task.Sequence_Step__c`, **and**
  the matched step is `CallCompleted`, set
  `Next_Action_Date__c = Datetime.now().addDays(Integer.valueOf(Days_Until_Next_Email__c))`
  (R4). One Target update (R8).

## Recursion & bulkification (R7, R8, R9)

- Static `Set<Id>` guards in each handler (Rule R3) — never a static Boolean.
- One SOQL for related records, one DML per handler; 200-record safe.
- `TaskTrigger` is the only trigger on `Task`; if a Task trigger already exists in the org,
  add a handler call instead of a second trigger (R9, slicing-guide).

## Security (§9)

- Handlers `with sharing`; SOQL via selectors (USER_MODE); DML `Database.update(...,
  AccessLevel.USER_MODE)` with partial-success handling.
- Queueable does no callouts; standard async limits apply.

## Test approach (§12)

- `TargetTriggerHandlerTest`: insert active target → assert queueable enqueued and (after
  `Test.stopTest`) step-1 artifacts exist. Insert inactive → nothing.
- `TaskTriggerHandlerTest`: complete a matching `Call 1` task → `Next_Action_Date__c` set
  (≈ now + `Days_Until_Next_Email__c`); complete a non-sequence task → unchanged (R5);
  inactive target → unchanged (R6); step mismatch → unchanged; complete a Call on a Timer
  step (e.g. step 6) → `Next_Action_Date__c` unchanged (R10).
- **Bulk:** 200 inserts and 200 task completions — one DML per object, no governor errors.
- `@testSetup`, `Test.startTest/stopTest` (forces queueable to run); email in test context.
- Coverage target **>= 85%** (handlers/queueable).

## Resolved decisions / discrepancies

- **Stall behavior = leave paused** (confirmed 2026-06-12). Call-driven steps pause until
  the call completes; **no fallback timer** is implemented. The `CallCompleted` path simply
  leaves `Next_Action_Date__c` null until the rep completes the call.
- **Call-completion reschedule gated on `Next_Trigger_Type__c` (2026-06-15).** Call tasks
  exist on every step, including Timer steps (6–9). `TaskTriggerHandler` must read
  `Sequence_Step_Config__mdt` (via `SequenceStepConfigService`) for the matched step and
  only reschedule when `Next_Trigger_Type__c == 'CallCompleted'`; otherwise it is a no-op
  so the engine-set timer is not overwritten (R4, R10).
