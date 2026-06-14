# Design — 05_terminal_stop_and_guards

**Source:** Target_Sequence_Solution_Design.md §2 (Feature 11), §4.2, §3.4, §8; slicing-guide

## Approach

Extend — do not duplicate. Feature 03 created `TargetTrigger` (after-insert) and
`TargetTriggerHandler`. This feature adds the **before-update** branch for the
terminal-status stop. Before-save is chosen because it's a same-record field update: the
handler mutates `Trigger.new` directly, so there's **no extra DML** (Order of Execution,
§4.2). The terminal set is data (`Sequence_Terminal_Status__mdt`), so the stop list is
admin-tunable.

## Data-model prerequisite (R8)

The `Target__c.Status__c` **restricted** picklist value set must contain the four terminal
values `Converted`, `Meeting Booked`, `Do Not Contact`, `Replied` (added via the field's
`valueSetDefinition`). Without them, a restricted-picklist save of a terminal status fails
(`INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`) and R1 is unreachable. The terminal **match**
itself stays metadata-driven via `Sequence_Terminal_Status__mdt` (R5) — no code or CMDT
change; only the value set is extended.

## Class changes (one-trigger-per-object)

```
triggers/
  TargetTrigger.trigger        // ADD `before update` to the existing trigger from 03
classes/
  TargetTriggerHandler.cls     // ADD beforeUpdate(newList, oldMap) branch
  // Sequence_Terminal_Status__mdt read via a small cached lookup (getAll())
```

> Route by `Trigger.operationType` in `TargetTriggerHandler`: `AFTER_INSERT` → start
> (03); `BEFORE_UPDATE` → terminal stop (this feature). Slicing-guide: a single trigger
> file with two branches, reasoned about separately.

## beforeUpdate logic (R1–R4)

1. Build the terminal map once: `Map<String,String> stopReasonByStatus` from
   `Sequence_Terminal_Status__mdt.getAll()` (R5; no SOQL).
2. For each record in `Trigger.new`:
   - `String newStatus = rec.Status__c;`
   - Skip if `oldMap.get(rec.Id).Status__c == newStatus` (status unchanged — R3).
   - Skip if `rec.Sequence_Active__c == false` (already stopped — R4).
   - If `stopReasonByStatus.containsKey(newStatus)`: set `rec.Sequence_Active__c = false`,
     `rec.Sequence_Stop_Reason__c = stopReasonByStatus.get(newStatus)`,
     `rec.Next_Action_Date__c = null` (R1). **No DML** — these mutate `Trigger.new`.
3. Static `Set<Id>` recursion guard shared with the handler (R7).

## Kill switch confirmation (R6)

- No new code: the entry points (03) and batch (04) already filter/guard on
  `Sequence_Active__c`. This feature adds **tests** proving that flipping the flag false
  (auto via R1, or manual uncheck) stops advancement and sending (Solution Design §12
  steps 5–6).

## Security (§9)

- `with sharing` handler; before-save mutation needs no DML and no extra FLS beyond the
  fields already in `Trigger.new`. `Sequence_Terminal_Status__mdt` via `getAll()`.

## Bulkification (R7)

- Pure in-memory mutation of `Trigger.new`; 200-record safe with zero DML and zero added
  SOQL (CMDT is cached).

## Test approach (§12 steps 5–6)

- `TargetTriggerHandlerTest` (extend from 03): update active target to each terminal
  status → assert `Sequence_Active__c=false`, correct `Sequence_Stop_Reason__c`,
  `Next_Action_Date__c=null`, and `Limits.getDmlStatements()` shows no extra DML for the
  stamp (R1, R2).
- Status unchanged → no stop (R3). Already inactive → no change (R4).
- Non-terminal status change → no stop.
- **Kill switch:** seed a mid-cadence active target, deactivate (auto + manual), run the
  scheduler (04) → assert no email/step change (R6).
- **Bulk:** 200 updates to terminal statuses in one transaction (R7).
- Coverage target **>= 85%** (combined with 03's handler tests).

## Open items / discrepancies

- None unique to this feature.
