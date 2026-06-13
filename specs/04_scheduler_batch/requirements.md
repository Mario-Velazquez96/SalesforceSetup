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
**R2 (Event-driven):** When `SequenceSchedulerBatch.start` runs, it shall return a `QueryLocator` for `Target__c` filtering on `Sequence_Active__c = true AND Next_Action_Date__c <= :now AND Sequence_Step__c < 10` (`WITH USER_MODE`). Because `start()` returns a Batch `QueryLocator`, the filter is not required to be selective.
**R3 (Event-driven):** When the batch `execute` processes a due target, it shall call `SequenceEngineService.processStep(target, target.Sequence_Step__c + 1)`.
**R4 (Ubiquitous):** `SequenceSchedulerSchedulable` shall implement `Schedulable`, execute `SequenceSchedulerBatch` with scope 200, and be schedulable via CRON (default: every 8 hours).
**R5 (Unwanted behavior):** If a target became inactive between `start` and `execute`, then the engine's kill-switch guard (02/R7) shall prevent the send (defensive double-check).
**R6 (Ubiquitous):** Each `execute` shall be bulkified (one DML per object) and rely on per-execute fresh governor limits; scope shall not exceed 200.
**R7 (State-driven):** While the org is below the Apex single-email daily cap, the batch shall send due emails; the batch shall not exceed that cap within a run (operational guard / monitoring).
**R8 (Ubiquitous):** The batch query shall remain performant at the org's expected `Target__c` volume; performance relies on the Batch `start()` QueryLocator (which does not require a selective filter) rather than on a custom index.

## Acceptance

- A target at `Sequence_Step__c=6` with a past `Next_Action_Date__c` advances to step 7
  (Email 7, `Call 7`, `Next_Action_Date__c ≈ now + 7d`) on the next batch run; running the
  batch four times walks 6→10 with the 14/7/14/14 cadence (Solution Design §6, §12 step 3).
- A target whose `Next_Action_Date__c` is in the future is not selected.
- An inactive target is never advanced.

## Resolved decisions (approval gate)

- **Schedule frequency = every 8 hours** (revised, 2026-06-13 — supersedes the prior
  2026-06-12 daily decision of CRON `0 0 6 * * ?`). The schedulable runs three times per
  day via CRON; the cadence waits (e.g. the 4-day call wait and the 14/7/14/14 timers) are
  realized on the **first scheduled run on/after the due `DateTime`** — now within ~8 hours
  of the due time rather than up to a full day. `Next_Action_Date__c` stays a `DateTime`
  (no change to feature 01), so the 8-hourly poll keeps that DateTime precision meaningful:
  a target that becomes due mid-day is picked up within ~8 hours. (Was §10 item 3.)
- **Apex email cap = confirmed clear** — expected daily target volume stays under the
  5,000 single-emails/org/day limit; no throttling needed now. Monitor in production.
  (Was §10 item 2.)
- **Custom index on `Next_Action_Date__c` DROPPED (2026-06-13).** The prior dependency on a
  custom index (feature 01 former R15) is removed. The batch reads due targets via a
  `Database.getQueryLocator` in `start()`; Batch `start()` QueryLocators are exempt from the
  "non-selective query against a large object" exception, so the query runs without a custom
  index — the index was only a performance optimization, not a correctness requirement, and
  the org expects modest `Target__c` volume. R2/R8 reworded accordingly; no other R-numbers
  change.

## Open items

- None.
