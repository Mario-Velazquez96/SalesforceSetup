# Requirements — 05_terminal_stop_and_guards

**Feature:** Auto-stop the cadence on terminal status; confirm the manual kill switch
**Source:** Target_Sequence_Solution_Design.md §2 (Feature 11), §4.2, §3.4, §8 (kill switch)
**Depends on:** 03_event_entry_points

## Purpose

Add Feature 11: when a `Target__c` reaches a terminal `Status__c`, automatically deactivate
the sequence and record why. This is a **before-update branch added to the existing
`TargetTrigger`** from feature 03 (one trigger per object). Also confirm the manual
kill-switch path (`Sequence_Active__c` unchecked) halts all advancement.

## In scope

- `TargetTriggerHandler` **before-update** branch (terminal-status stop).
- `TargetTrigger` updated to invoke the handler in the `before update` context.
- Verification that an inactive target is never advanced by 03/04 (kill switch).

## Out of scope

- A new trigger — this **extends** the `TargetTrigger`/`TargetTriggerHandler` from 03.
- The engine guard itself (defined in 02/R7) — here we verify the manual-uncheck path.

## Requirements (EARS)

**R1 (Event-driven):** When a `Target__c` is updated such that `Status__c` changed to a value present in `Sequence_Terminal_Status__mdt` and `Sequence_Active__c` is currently true, the system shall set `Sequence_Active__c = false`, `Sequence_Stop_Reason__c =` the matching `Stop_Reason__c`, and `Next_Action_Date__c = null`.
**R2 (Ubiquitous):** R1 shall execute in the `TargetTrigger` **before-update** context (same-record field updates, **no** additional DML) and shall be implemented as a branch of the existing `TargetTrigger`/`TargetTriggerHandler` — not a second trigger.
**R3 (Unwanted behavior):** If `Status__c` did not change in the update, then no stop action shall occur.
**R4 (Unwanted behavior):** If `Sequence_Active__c` is already false, then no stop action shall occur.
**R5 (State-driven):** While the terminal-status set is defined by `Sequence_Terminal_Status__mdt`, adding/removing a terminal status shall be a metadata edit, not a code change.
**R6 (Unwanted behavior):** If `Sequence_Active__c` is false (auto- or manually unchecked), then the entry points (03) and scheduler (04) shall not advance or send for that target.
**R7 (Ubiquitous):** The before-update branch shall be bulkified (200-record safe) and use a static `Set<Id>` recursion guard consistent with feature 03.

## Acceptance

- Setting `Status__c='Converted'` (or Meeting Booked / Do Not Contact / Replied) on an
  active target flips `Sequence_Active__c=false`, writes `Sequence_Stop_Reason__c`, and
  clears `Next_Action_Date__c` — with no extra DML.
- A subsequent scheduler run sends nothing for that target.
- Manually unchecking `Sequence_Active__c` mid-cadence stops further sends (Solution Design
  §12 steps 5–6).

## Open items

- None specific to this feature. (Terminal status list confirmed in 01; "RE: subject only"
  and stall-risk items belong to 02/03.)
