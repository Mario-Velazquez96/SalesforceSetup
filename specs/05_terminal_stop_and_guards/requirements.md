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
- Mapping the `Sequence_Terminal_Status__mdt` terminal set to the **existing**
  `Target__c.Status__c` restricted picklist values (`Closed`, `Target Not Interested`,
  `Client Not Interested`, `Conflicted`) so R1 is reachable **without** adding new picklist
  values (R8; see Resolved decisions 2026-06-15).

## Out of scope

- Adding any new value to the `Target__c.Status__c` restricted value set — the terminal set
  reuses **existing** values only (see Resolved decisions 2026-06-15).
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
**R8 (Ubiquitous):** The terminal-status values shall be drawn from the EXISTING `Target__c.Status__c` restricted value set (`Closed`, `Target Not Interested`, `Client Not Interested`, `Conflicted`); no new picklist values are added for the cadence.

## Acceptance

- Setting `Status__c='Closed'` (or `Target Not Interested` / `Client Not Interested` /
  `Conflicted`) on an active target is a **valid, reachable** update (the value already
  exists in the restricted picklist — R8) that flips `Sequence_Active__c=false`, writes
  `Sequence_Stop_Reason__c`, and clears `Next_Action_Date__c` — with no extra DML.
- A subsequent scheduler run sends nothing for that target.
- Manually unchecking `Sequence_Active__c` mid-cadence stops further sends (Solution Design
  §12 steps 5–6).

## Resolved decisions (approval gate)

### 2026-06-15 — client reversal (SUPERSEDES the 2026-06-13 decision below)

- **Reversal:** The client reverted the picklist additions. **No new values** are added to
  `Target__c.Status__c`. The four previously-added design values (`Converted`,
  `Meeting Booked`, `Do Not Contact`, `Replied`) are **removed** from the `Status__c`
  restricted value set, and their `Sequence_Terminal_Status__mdt` rows are **replaced**.
- **New terminal set:** The cadence auto-stops on the **existing** `Status__c` values
  `Closed`, `Target Not Interested`, `Client Not Interested`, `Conflicted` (captured as the
  revised R8). `Sequence_Terminal_Status__mdt` maps each of these existing values to its
  `Stop_Reason__c`.
- **Mechanism unchanged:** The terminal **match** stays metadata-driven via
  `Sequence_Terminal_Status__mdt` (R1, R5) — only the value set referenced by the CMDT rows
  changes; the `Status__c` value set itself is **not** modified by this feature.

### 2026-06-13 — original decision (SUPERSEDED by 2026-06-15 above)

- **Issue (found during implementation):** `Target__c.Status__c` is a **restricted**
  picklist whose value set did **not** include the four terminal values then referenced by
  `Sequence_Terminal_Status__mdt` (`Converted`, `Meeting Booked`, `Do Not Contact`,
  `Replied`). As a result the R1 terminal-stop branch could never fire — any attempt to set
  one of those statuses failed with `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`.
- **Decision (human-approved, now reversed):** **Add** those four design values to the
  `Status__c` restricted value set and **keep** the `Sequence_Terminal_Status__mdt` terminal
  set as exactly those same four. This decision is **superseded** by the 2026-06-15 reversal
  above.

## Open items

- None specific to this feature. (Terminal status list confirmed in 01; "RE: subject only"
  and stall-risk items belong to 02/03.)
