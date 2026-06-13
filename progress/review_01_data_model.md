# Review — 01_data_model

**Reviewer run:** 2026-06-13 against org `BlueSky` (sandbox, API 66.0).
**Verdict: REJECT** — one requirement (R9/R10) is not satisfied in the org; the
"async propagation" explanation in the implementer report is disproven by a control test.

---

## What was verified GREEN

- **R1–R8 (Target__c fields):** All 8 fields present in org via global describe
  (`sequence_active__c, sequence_step__c, days_until_next_email__c,
  sequence_stop_reason__c, next_action_date__c, primary_contact__c,
  sequence_attachment_id__c, billing_city__c` = true). Field-meta files match
  spec types/defaults. R8 formula = `Company_Name__r.BillingCity`.
- **R11 (Sequence_Step_Config__mdt):** Object + all 7 fields present
  (Step_Number__c, Email_Template_Dev_Name__c, Is_Reply__c, Call_Task_Subject__c,
  Call_Due_Offset_Days__c, Next_Trigger_Type__c, Next_Wait_Days__c).
- **R12 (10 step rows):** `getAll().size()=10`. Full row dump matches Design §Rows
  exactly: steps 1–5 CallCompleted (wait=null); steps 6–9 Timer with
  Next_Wait_Days 14/7/14/14; step 10 None; Is_Reply true for 2–10, false for 1;
  Call_Due_Offset_Days=2 throughout; templates Sequence_Email_N.
  Step_6 spot-check: trig=Timer, wait=14.0, reply=true. PASS.
- **R13 (Sequence_Terminal_Status__mdt + 4 rows):** Object + 2 Text fields present;
  `getAll().size()=4`; rows Converted / Meeting Booked / Do Not Contact / Replied,
  Status_Value__c and Stop_Reason__c match Design.
- **R14 (email templates):** 10 EmailTemplate records `Sequence_Email_%` in org.
  Email_3 contains all three merge fields ({{{Target__c.Name}}},
  {{{Contact.FirstName}}}, {{{Target__c.Billing_City__c}}}). Email_1 has
  Target Name + Contact (Billing City scoped to Email 3 per spec).
- **R15 (custom index):** File `customIndexes/Target_Next_Action_Date.indx-meta.xml`
  authored and correctly EXCLUDED from package.xml — accepted spec-acknowledged
  operational deferral (Support case). OK.
- **R16 (perm-set FLS) — metadata + persistence:** Both `Login_Sequence_User` and
  `Login_Sequence_Admin` carry 12 FieldPermissions in org, including the 8
  Target__c fields (Billing_City__c read-only) and the four cadence entries
  Task.Is_Sequence_Call__c, Task.Sequence_Step__c, Event.Is_Sequence_Call__c,
  Event.Sequence_Step__c. Admin additionally has read/viewAll on both CMDTs and
  ModifyMetadata. FLS metadata is correct.
- **R17 (API version):** sfdx-project.json sourceApiVersion=66.0; package.xml
  version 66.0.
- **Conventions / scope:** Field/CMDT/perm-set naming follows project patterns;
  no objects/fields beyond the spec; no Apex in this feature (declarative-only,
  no coverage applies, per tasks.md Verification). OK.

---

## BLOCKING FINDINGS

### Finding 1 (R9/R10) — Cadence fields are NOT functionally present on Task/Event

The fields were moved to the `Activity` object and deployed there (retrieve
confirms `Activity.Is_Sequence_Call__c` and `Activity.Sequence_Step__c` persist).
However, they do NOT reflect onto Task/Event, which is what R9/R10 require:

- `SELECT Id, Is_Sequence_Call__c, Sequence_Step__c FROM Task LIMIT 1`
  → `No such column 'Is_Sequence_Call__c' on entity 'Task'`.
- Same query on `Event` → identical `No such column` error.
- Global describe: `Task` field map `is_sequence_call__c`=false, `sequence_step__c`=false;
  `Event` map both = false.
- Tooling `FieldDefinition` for these QualifiedApiNames on Task/Event/Activity
  returns ZERO rows.

**The implementer's "async propagation lag" theory is disproven.** A control test
in the SAME describe run shows the org's PRE-EXISTING Activity custom fields DO
reflect onto Task (`company__c`=true, `target__c`=true on Task). The reflection
mechanism works; these two new fields specifically fail to surface ~1 day after
deploy. This is a real defect, not in-flight propagation. (Note: FLS for
Task.*/Event.* entries was accepted by the org, which is misleading — FLS at the
EntityParticle layer can persist even though the fields are not queryable; do not
treat that as evidence the requirement is met.)

This blocks all downstream features that read these fields on Task (e.g. the
trigger/engine in 03/05 that detects sequence call tasks).

**Action items for the implementer:**
1. Determine why `Activity.Is_Sequence_Call__c` / `Activity.Sequence_Step__c`
   do not reflect to Task/Event when pre-existing Activity custom fields do.
   Likely causes to check: the fields were created/deployed on `Activity` but the
   org's Shared Activities / field-reflection requires them to also be surfaced on
   the Task/Event page-layout/entity (some Activity fields require re-save or
   were created via an unsupported path). Verify in Setup whether the two new
   fields appear under Setup > Object Manager > Activities > Fields and whether
   they show "Tasks/Events" availability.
2. Once corrected, re-verify in anonymous Apex against `BlueSky` that BOTH
   `SELECT Id, Is_Sequence_Call__c, Sequence_Step__c FROM Task LIMIT 1` and the
   `Event` equivalent execute WITHOUT error (expect REFLECT_OK), and that the
   global describe field maps for Task and Event both return true for the two
   fields.
3. Re-confirm the perm-set FLS still resolves after the fields become queryable
   (re-deploy perm sets if needed so FLS binds to live fields).

### Finding 2 (tasks.md accuracy)

`tasks.md` line 8 marks the cadence-field task `- [x]` "DEPLOYED ... and verified
present on Activity". Given Finding 1, the requirement R9/R10 ("on `Task`") is NOT
met. The checkbox overstates completion. Re-flag this task (e.g. `- [~]`/`- [ ]`)
until Task/Event reflection is verified. (The implementer report itself is more
honest — it lists this as an outstanding runtime assertion in Blocker #1 — but the
deferred state was never resolved; the review confirms it still fails.)

---

## Summary

13 of the 17 requirements (R1–R8, R11–R14, R16-metadata, R17) plus the R15 deferral
are verified. R9 and R10 fail in-org verification. Per the SDD gate, the feature
cannot be marked `done`. Resolve Findings 1 and 2, then resubmit for review.

---

## Re-review (2026-06-13)

**Verdict: APPROVE.** The previously-blocking R9/R10 finding is resolved.
Root cause confirmed as FLS visibility (the prior verifying user lacked read
on the cadence fields), not a reflection defect. Re-verified in-org against
`BlueSky` (sandbox, API 66.0); no regressions found.

### Evidence — R9/R10 now satisfied (previously-blocking finding)

Anonymous Apex run against `BlueSky` (script reached `REFLECT_OK`):

- `SELECT Id, Is_Sequence_Call__c, Sequence_Step__c FROM Task LIMIT 1` →
  executed cleanly, 1 row, **no "No such column"**.
- `Event` equivalent → executed cleanly, 0 rows (org has no Event data),
  **no "No such column"**.
- `Schema.SObjectType.Task.fields.getMap()` `containsKey` `is_sequence_call__c`
  = true and `sequence_step__c` = true; both `isAccessible()` = true.
- `Schema.SObjectType.Event.fields.getMap()` `containsKey` both fields = true;
  both `isAccessible()` = true.

(FieldDefinition tooling query was not separately re-run via CLI due to a
local shell-shim redirection bug on this Windows host — unrelated to the org.
The describe `containsKey`=true + `isAccessible`=true + successful SOQL on both
Task and Event is strictly stronger evidence that the fields are present and
queryable, so this finding is conclusively cleared.)

### Evidence — FLS fix (R16), no regression

`FieldPermissions` query in-org:

- **Cadence FLS:** 8 rows (4 fields × 2 perm sets). All of
  `Task.Is_Sequence_Call__c`, `Task.Sequence_Step__c`,
  `Event.Is_Sequence_Call__c`, `Event.Sequence_Step__c` on BOTH
  `Login_Sequence_User` and `Login_Sequence_Admin` carry
  `PermissionsRead=true` and `PermissionsEdit=true`.
- **Target__c FLS (regression check):** 16 rows (8 fields × 2 perm sets); all
  8 Target__c fields still present on both perm sets
  (Sequence_Active__c, Sequence_Step__c, Days_Until_Next_Email__c,
  Sequence_Stop_Reason__c, Next_Action_Date__c, Primary_Contact__c,
  Sequence_Attachment_Id__c, Billing_City__c). No regression.

### Evidence — CMDT / templates / API version (regression check)

Anonymous Apex against `BlueSky`:

- `Sequence_Step_Config__mdt.getAll().size()` = 10; Step_6 spot-check
  `Next_Trigger_Type__c=Timer, Next_Wait_Days__c=14.0, Is_Reply__c=true`.
- `Sequence_Terminal_Status__mdt.getAll().size()` = 4.
- `EmailTemplate WHERE DeveloperName LIKE 'Sequence_Email_%'` COUNT = 10.
- `sfdx-project.json sourceApiVersion=66.0`; `package.xml version=66.0`.

### Evidence — scope discipline

Cadence fields live on `Activity` (reflected to Task/Event) — the supported
mechanism; the stale `objects/Task/fields/Is_Sequence_Call__c` /
`Sequence_Step__c` files were removed (only standard Task fields remain in that
folder). No metadata beyond the spec.

### Tasks.md

`tasks.md` line 8 now accurately marks R9/R10 `- [x]` with the FLS-root-cause
explanation and the Task/Event end-to-end verification. R15 remains `- [~]`
(spec-acknowledged Support-case deferral). Accurate.

### Disposition

All 17 requirements verified (R1–R14, R16, R17) plus the R15 operational
deferral. Findings 1 and 2 from the original review are resolved. **The leader
may mark `01_data_model` as `done`.**
