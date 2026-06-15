# Requirements — 03_event_entry_points

**Feature:** Triggers + queueable that start the sequence and react to call completion
**Source:** Target_Sequence_Solution_Design.md §2 (Features 1, 2–6), §4.2 (Event capture), §9
**Depends on:** 02_core_engine

## Purpose

Wire the engine to platform events: start the cadence when a `Target__c` is created
(Feature 1), and set the next-action due date when a sequence `Call N` Task is completed
(Features 2–6). All real work delegates to `SequenceEngineService`; the actual sending of
the next email is deferred to the scheduler (04).

## In scope

- `TargetTrigger` (after-insert branch) + `TargetTriggerHandler`.
- `SequenceStartQueueable` (off-trigger start of step 1).
- `TaskTrigger` (after-update) + `TaskTriggerHandler` (call-completion → set
  `Next_Action_Date__c`).

## Out of scope

- `TargetTrigger` **before-update** terminal-stop branch → `05_terminal_stop_and_guards`
  (adds to the *same* trigger file built here).
- The batch that actually sends due steps → `04_scheduler_batch`.

## Requirements (EARS)

**R1 (Event-driven):** When a `Target__c` is inserted, the system shall enqueue `SequenceStartQueueable` with the new record Ids.
**R2 (Event-driven):** When `SequenceStartQueueable` executes, it shall call `SequenceEngineService.processStep(target, 1)` for each new target (Feature 1: Email 1 + `Call 1` task + completed Email activity + `Sequence_Step__c=1`).
**R3 (Ubiquitous):** `TargetTrigger` shall be the **only** trigger on `Target__c`, contain no business logic, and delegate to `TargetTriggerHandler`.
**R4 (Event-driven):** When a `Task` is updated to `Status='Completed'` with `Is_Sequence_Call__c=true`, and the related `Target__c` is active with `Sequence_Step__c` equal to the Task's `Sequence_Step__c`, AND the matched step's `Sequence_Step_Config__mdt.Next_Trigger_Type__c` is `'CallCompleted'`, the system shall set that target's `Next_Action_Date__c = now + Days_Until_Next_Email__c`.
**R5 (Unwanted behavior):** If the updated `Task` has `Is_Sequence_Call__c=false` (e.g. a logged Email activity), then the system shall take no action.
**R6 (Unwanted behavior):** If the related `Target__c.Sequence_Active__c` is false, then no `Next_Action_Date__c` update shall occur.
**R7 (Ubiquitous):** Trigger recursion shall be prevented with a static `Set<Id>` (not a static `Boolean`).
**R8 (Ubiquitous):** Both handlers shall be bulkified — one query for related targets, one DML — and safe for 200-record transactions.
**R9 (Ubiquitous):** `TaskTrigger` shall be the only trigger on `Task`; if one already exists, add a handler call rather than a second trigger.
**R10 (Unwanted behavior):** If the completed sequence Call's matched step is a Timer or None step (`Sequence_Step_Config__mdt.Next_Trigger_Type__c != 'CallCompleted'`), then no `Next_Action_Date__c` change shall occur — the engine-set timer governs.

## Acceptance

- Inserting an active `Target__c` (with `Primary_Contact__c`) results in Email 1, an open
  `Call 1` task, a completed Email task, and `Sequence_Step__c=1` (via the queueable).
- Marking that `Call 1` task Completed sets `Next_Action_Date__c ≈ now +
  Days_Until_Next_Email__c`; no email is sent yet (that's 04).
- Completing a non-sequence task, or a sequence task whose step doesn't match, changes
  nothing.
- Completing a Call on a **CallCompleted** step (steps 1–5) sets `Next_Action_Date__c ≈
  now + Days_Until_Next_Email__c`.
- Completing a Call on a **Timer** step (e.g. step 6) leaves `Next_Action_Date__c`
  unchanged — the engine-set 14-day timer stands.

## Resolved decisions (approval gate, 2026-06-12)

- **Stall behavior = leave paused** (confirmed). For call-driven steps 1–6, if a rep never
  completes `Call N`, `Next_Action_Date__c` stays null and the cadence pauses indefinitely
  — this is the intended behavior. **No fallback timer** is built. (Was §10 item 1.)

## Resolved decisions (bug refinement, 2026-06-15)

- **Call-completion reschedule is gated on `Next_Trigger_Type__c == 'CallCompleted'`.**
  The engine creates a `Call N` task on **every** step, including Timer steps (6–9) where
  the engine already sets `Next_Action_Date__c = now + Next_Wait_Days__c` (14/7/14/14).
  Previously R4 rescheduled on *any* completed sequence Call, so completing the Call on a
  Timer step overwrote the engine-set 14-day timer with the 4-day call wait (a bug).
  R4 now only reschedules when the matched step's config `Next_Trigger_Type__c` is
  `'CallCompleted'` (steps 1–5); for Timer/None steps the handler is a no-op (R10) and the
  engine-set timer governs.

## Open items

- None.
