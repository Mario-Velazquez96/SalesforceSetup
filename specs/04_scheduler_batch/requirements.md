# Requirements — 04_scheduler_batch

**Feature:** Daily batch + schedulable that advance every target whose next action is due
**Source:** Target_Sequence_Solution_Design.md §2 (Features 7–10), §4.2, §6 (timeline), §10
**Depends on:** 02_core_engine

## Purpose

Realize the waits. A scheduled batch finds active targets whose `Next_Action_Date__c` has
arrived and advances each to its next step via the engine. This single job covers **both**
the configurable 4-day call waits (set by 03) and the fixed 14/7/14/14 timers (set by the
engine in 02), so there is one advancement mechanism rather than ten flows.

## In scope

- `SequenceSchedulerBatch` (`Database.Batchable<sObject>`, `Database.Stateful`).
- `SequenceSchedulerSchedulable` (`Schedulable`) + the CRON scheduling helper.

## Out of scope

- The per-step send logic (engine, 02) — invoked, not duplicated here.
- Setting `Next_Action_Date__c` on call completion (03) — this feature only consumes it.

## Requirements (EARS)

**R1 (Ubiquitous):** `SequenceSchedulerBatch` shall implement `Database.Batchable<sObject>` and `Database.Stateful`.
**R2 (Event-driven):** When `SequenceSchedulerBatch.start` runs, it shall return a `QueryLocator` for `Target__c` where `Sequence_Active__c = true AND Next_Action_Date__c <= :now AND Sequence_Step__c < 10` (`WITH USER_MODE`, selective on the indexed fields).
**R3 (Event-driven):** When the batch `execute` processes a due target, it shall call `SequenceEngineService.processStep(target, target.Sequence_Step__c + 1)`.
**R4 (Ubiquitous):** `SequenceSchedulerSchedulable` shall implement `Schedulable`, execute `SequenceSchedulerBatch` with scope 200, and be schedulable via CRON (default: once daily).
**R5 (Unwanted behavior):** If a target became inactive between `start` and `execute`, then the engine's kill-switch guard (02/R7) shall prevent the send (defensive double-check).
**R6 (Ubiquitous):** Each `execute` shall be bulkified (one DML per object) and rely on per-execute fresh governor limits; scope shall not exceed 200.
**R7 (State-driven):** While the org is below the Apex single-email daily cap, the batch shall send due emails; the batch shall not exceed that cap within a run (operational guard / monitoring).
**R8 (Ubiquitous):** The batch query shall be selective (indexed `Next_Action_Date__c` + `Sequence_Active__c`) to remain performant at LDV.

## Acceptance

- A target at `Sequence_Step__c=6` with a past `Next_Action_Date__c` advances to step 7
  (Email 7, `Call 7`, `Next_Action_Date__c ≈ now + 7d`) on the next batch run; running the
  batch four times walks 6→10 with the 14/7/14/14 cadence (Solution Design §6, §12 step 3).
- A target whose `Next_Action_Date__c` is in the future is not selected.
- An inactive target is never advanced.

## Resolved decisions (approval gate, 2026-06-12)

- **Schedule frequency = daily** (confirmed) — CRON `0 0 6 * * ?` (06:00). "4 days" = the
  first daily run on/after the due date. (Was §10 item 3.)
- **Apex email cap = confirmed clear** — expected daily target volume stays under the
  5,000 single-emails/org/day limit; no throttling needed now. Monitor in production.
  (Was §10 item 2.)

## Open items

- None.
