# Implementation report — 01_data_model

Feature: Data model (declarative metadata only). Spec: `specs/01_data_model/`.
Implementer run date: 2026-06-12. Target org: `BlueSky` (sandbox,
`power-customization-9206--inouvia.sandbox.my.salesforce.com`, API 66.0).

## Status

In progress / pending re-review. All metadata authored; deploy-validate + data
checks recorded below. R9/R10 reviewer rejection RESOLVED (2026-06-13): cadence
fields confirmed present and queryable on Task and Event; root cause was FLS
visibility, fixed and end-to-end verified (see R9/R10, R16, and resolved Blocker #1).

## Files created / changed

### Target__c fields (R1–R8)
- `force-app/main/default/objects/Target__c/fields/Sequence_Active__c.field-meta.xml` (Checkbox, default true) — R1
- `.../Sequence_Step__c.field-meta.xml` (Number(2,0), default 0) — R2
- `.../Days_Until_Next_Email__c.field-meta.xml` (Number(3,0), default 4) — R3
- `.../Sequence_Stop_Reason__c.field-meta.xml` (Text(255)) — R4
- `.../Next_Action_Date__c.field-meta.xml` (DateTime) — R5
- `.../Sequence_Attachment_Id__c.field-meta.xml` (Text(18)) — R7
- `.../Billing_City__c.field-meta.xml` (Text formula = `Company_Name__r.BillingCity`) — R8
- R6 (`Primary_Contact__c`, Lookup→Contact) ALREADY EXISTED in the repo and
  matches the spec exactly; not recreated. FLS for it is added by the new perm sets.

### Cadence activity fields (R9–R10) — moved Task → Activity (2026-06-13)
- `force-app/main/default/objects/Activity/fields/Is_Sequence_Call__c.field-meta.xml` (Checkbox) — R9
- `force-app/main/default/objects/Activity/fields/Sequence_Step__c.field-meta.xml` (Number(2,0)) — R10
- The two stale files under `objects/Task/fields/` were DELETED. Custom fields for
  Task/Event cannot be created on the `Task` object directly (root cause of the
  original `bad value for restricted picklist field: Task` deploy error). They are
  created on the standard `Activity` object, which reflects them onto both `Task`
  and `Event` — the supported Salesforce mechanism. Field definitions are otherwise
  unchanged (API 66.0, same labels/types). The `objects/Activity/` folder already
  existed in the repo (pre-existing custom fields `Company__c`, `Target__c`,
  `State__c`, `Account_State__c`), so the structure was mirrored, not created.

### CMDT Sequence_Step_Config__mdt (R11–R12)
- Object: `.../objects/Sequence_Step_Config__mdt/Sequence_Step_Config__mdt.object-meta.xml`
- 7 fields: `Step_Number__c` (Number), `Email_Template_Dev_Name__c` (Text),
  `Is_Reply__c` (Checkbox), `Call_Task_Subject__c` (Text),
  `Call_Due_Offset_Days__c` (Number), `Next_Trigger_Type__c`
  (restricted Picklist: CallCompleted / Timer / None), `Next_Wait_Days__c` (Number).
- 10 records `.../customMetadata/Sequence_Step_Config.Step_1..10.md-meta.xml`
  per Design §Rows: steps 1–5 CallCompleted; 6–9 Timer with Next_Wait_Days
  14/7/14/14; step 10 None; Is_Reply true for 2–10; Call_Due_Offset_Days = 2;
  Call_Task_Subject = "Call N"; Email_Template_Dev_Name = Sequence_Email_N.

### CMDT Sequence_Terminal_Status__mdt (R13)
- Object + 2 fields `Status_Value__c`, `Stop_Reason__c` (both Text).
- 4 records: Converted, Meeting_Booked, Do_Not_Contact, Replied.

### Email templates (R14)
- Folder `.../email/Sequence_Emails.emailFolder-meta.xml`.
- 10 Lightning templates `.../email/Sequence_Emails/Sequence_Email_1..10`
  (`.email` HTML body + `.email-meta.xml`, `uiType=SFX`,
  `relatedEntityType=Target__c`). Merge fields:
  `[Target Name]` → `{{{Target__c.Name}}}`,
  `[Primary Contact]` → `{{{Contact.FirstName}}}`,
  `[Billing City]` → `{{{Target__c.Billing_City__c}}}` (used in Email 3).
  Subject = "Interest in {{{Target__c.Name}}}" on all 10 — the "RE:" prefix is
  NOT baked in (applied in Apex from Is_Reply__c per Design §Email Templates).

### Permission sets (R16)
- `.../permissionsets/Login_Sequence_User.permissionset-meta.xml` — FLS read/edit
  on all new Target__c + Task fields (Billing_City__c read-only as it is a formula).
- `.../permissionsets/Login_Sequence_Admin.permissionset-meta.xml` — same FLS plus
  read on both CMDT objects and `CustomizeApplication` to manage CMDT records.
- Apex class access intentionally omitted (added by later features — Design D2).

### Custom index (R15)
- `.../customIndexes/Target_Next_Action_Date.indx-meta.xml` authored but NOT
  included in package.xml. See Blockers.

### API version (R17)
- `sfdx-project.json` `sourceApiVersion` raised 58.0 → 66.0; `manifest/package.xml`
  already at version 66.0 and expanded to include every new component.

## Tasks (tasks.md)
- [x] Target__c fields R1–R7 (R6 pre-existing)
- [x] Billing_City__c formula R8
- [x] Cadence activity fields R9, R10 (on Activity, reflecting to Task/Event)
- [x] CMDT Sequence_Step_Config__mdt (7 fields) R11
- [x] 10 step rows R12
- [x] CMDT Sequence_Terminal_Status__mdt (2 fields) R13
- [x] 4 terminal-status rows R13
- [x] 10 Lightning email templates R14
- [~] Custom index R15 — authored, deferred (see Blockers)
- [x] Permission sets R16
- [x] API version 66.0 R17
- [x] Deploy-validate + data checks (results below)

## Email template format note

The 10 templates are classic HTML `EmailTemplate` (`type=custom`, `style=none`,
`uiType=Aloha`) in the `Sequence_Emails` folder. This format deploys reliably and
supports HML merge `{{{Object.Field}}}` for both Contact (recipient) and Target__c
(related-to), which is what the Apex send in `02_core_engine` needs via
`setTargetObjectId`/`setWhatId`. `uiType=SFX` (Lightning) + a classic EmailFolder
did not resolve the folder on deploy, and `type=html` requires a Letterhead;
`type=custom`/`style=none` is the correct no-letterhead full-HTML template. Named
HTML entities (`&rsquo;`, `&mdash;`, etc.) were replaced with literal UTF-8 chars
because the classic template parser is strict XML and rejects undeclared entities.

## Verification (target org: BlueSky sandbox, API 66.0)

All deploys used the v66.0 SOAP API. Results:

- **R1–R8 (Target fields):** DEPLOYED + VERIFIED. Anonymous Apex describe confirms
  all 8 fields present on `Target__c`: sequence_active__c, sequence_step__c,
  days_until_next_email__c, sequence_stop_reason__c, next_action_date__c,
  primary_contact__c, sequence_attachment_id__c, billing_city__c (all = true).
  The `Billing_City__c` formula (`Company_Name__r.BillingCity`) validated and
  deployed without error (R8 path confirmed valid).
- **R11/R13 (CMDT types + fields):** DEPLOYED + VERIFIED. Both CMDT objects and all
  their fields deployed; anonymous Apex `Sequence_Step_Config__mdt.getAll()` and
  `Sequence_Terminal_Status__mdt.getAll()` compile and execute (types exist).
- **R12/R13 (CMDT rows):** DEPLOYED + VERIFIED (2026-06-13). Root-cause of the prior
  failure was a malformed namespace declaration (see resolved Blocker #2). After the
  fix all 14 records deployed to `BlueSky` (`Created`, errors: 0). Anonymous Apex
  asserts pass: `Sequence_Step_Config__mdt.getAll().size()=10`,
  `Sequence_Terminal_Status__mdt.getAll().size()=4`, and Step_6 spot-check
  (`Next_Trigger_Type__c='Timer'`, `Next_Wait_Days__c=14`, `Is_Reply__c=true`).
- **R14 (email templates):** DEPLOYED + VERIFIED. SOQL count of EmailTemplate where
  DeveloperName LIKE 'Sequence_Email_%' = 10.
- **R9/R10 (cadence activity fields):** DEPLOYED to `Activity` and **FULLY VERIFIED on
  Task and Event (2026-06-13, re-verification run).** The reviewer's prior "No such column"
  / `describe map false` failure was a **field-level-security (FLS) visibility** issue for
  the running user — NOT a missing field. Proof gathered this run against `BlueSky`:
  1. **Field truly exists** — Tooling API `FieldDefinition` lists all six entries:
     `Is_Sequence_Call__c` (Checkbox) and `Sequence_Step__c` (Number(2,0)) on
     `Activity`, `Task`, AND `Event`. The Activity→Task/Event reflection is complete.
  2. **Direct SOQL succeeds with no column error** — `SELECT Id, Is_Sequence_Call__c,
     Sequence_Step__c FROM Task LIMIT 1` returned 1 row (`Is_Sequence_Call__c=false`,
     `Sequence_Step__c=null`); the `Event` equivalent returned 0 rows (org has no Event
     records) but executed cleanly — no `No such column`.
  3. **Anonymous Apex global describe maps** (running as `thomas@blueskyadvisory.com.inouvia`):
     `Schema.SObjectType.Task.fields.getMap()` and `...Event.fields.getMap()` both
     `containsKey` `is_sequence_call__c` and `sequence_step__c` = `true`; every field's
     `getDescribe().isAccessible()` = `true`; both SOQL queries inside the same script
     succeeded and the script reached `REFLECT_OK`.
  The original `bad value for restricted picklist field: Task` deploy error is also gone
  (fields target `Activity`, not `Task`). Blocker #1 is RESOLVED — see below.
- **R16 (permission sets):** DEPLOYED + VERIFIED with the final FLS approach, and
  **re-deployed + re-verified 2026-06-13** as the fix for the reviewer's R9/R10 rejection.
  Both perm sets express FLS for the Activity-reflected cadence fields as **both**
  `Task.<field>` and `Event.<field>` entries (Activity custom fields surface on both
  child objects; you reference them in `fieldPermissions` via the child object name,
  not `Activity.<field>`). Re-deploy 2026-06-13 (`sf project deploy start`,
  Deploy ID `0AfV900000CSOjdKAH`): `Succeeded`, 2/2 components, 0 errors
  (`Login_Sequence_Admin` Changed, `Login_Sequence_User` Unchanged — the org already
  matched the repo). Org-state confirmation via `FieldPermissions` query: on BOTH named
  perm sets (`0PSV9000000isazOAA` Admin, `0PSV9000000isb0OAA` User) all four entries
  — `Task.Is_Sequence_Call__c`, `Task.Sequence_Step__c`, `Event.Is_Sequence_Call__c`,
  `Event.Sequence_Step__c` — have `PermissionsRead=true` and `PermissionsEdit=true`
  (8 rows). **End-user FLS path validated:** `Login_Sequence_User` was assigned to a
  Standard User test account (Gabriel Silva, `005Vu00000JB5UTIA1`) — the kind of
  non-admin user that would have failed before — and a FieldPermissions query scoped to
  that user's assignments confirms the four cadence fields are reachable
  (`readable=true editable=true`) through the assignment. No entries had
  `readable=false`/missing readable, so no correction of existing entries was needed;
  the existing eight `Target__c` FLS entries were left untouched.
- **R17 (API version):** SATISFIED. `sourceApiVersion=66.0`; package.xml version 66.0.

## Blockers / notes (must be resolved before this feature is fully live)

1. **RESOLVED (2026-06-13) — cadence fields R9/R10 (root cause + fix).** The original
   `bad value for restricted picklist field: Task` error was caused by the field files
   living under `objects/Task/fields/`. In Salesforce, custom fields for Task/Event
   are NOT created on the `Task` object directly; they must be created on the standard
   `Activity` object, which reflects them onto both `Task` and `Event`. Fix applied:
   - Moved both fields to `objects/Activity/fields/Is_Sequence_Call__c.field-meta.xml`
     and `objects/Activity/fields/Sequence_Step__c.field-meta.xml`; deleted the stale
     `objects/Task/fields/` copies.
   - Updated `manifest/package.xml`: `Task.Is_Sequence_Call__c`/`Task.Sequence_Step__c`
     → `Activity.Is_Sequence_Call__c`/`Activity.Sequence_Step__c`, and the CustomObject
     member `Task` → `Activity`.
   - Deploy to `BlueSky` SUCCEEDED (2 components Created, 0 errors). The picklist error
     is gone. Retrieve-by-name confirms both fields persist on `Activity`.
   - Permission-set FLS deployed and persisted using `Task.<field>` + `Event.<field>`
     entries (the way Activity-reflected fields surface for FLS). See R16 above.

   **R9/R10 reviewer rejection — RESOLVED (2026-06-13 re-verification).** The reviewer
   reported the cadence fields as absent on Task/Event ("No such column", describe map
   false). Root cause (confirmed): the verifying user lacked FLS to view the two fields;
   the fields themselves exist on `Activity` and are reflected onto `Task`/`Event`. The
   field reflection is now fully complete and verified (no longer any async lag):
   - `FieldDefinition` (Tooling API) lists `Is_Sequence_Call__c` + `Sequence_Step__c` on
     `Activity`, `Task`, and `Event` (6 rows).
   - `SELECT Id, Is_Sequence_Call__c, Sequence_Step__c FROM Task LIMIT 1` → 1 row, no
     column error; the `Event` equivalent → 0 rows (no Event data), no column error.
   - Anonymous Apex describe maps for Task and Event both `containsKey` the two fields
     and report `isAccessible()=true`; script reaches `REFLECT_OK`.
   - FLS fix: both perm sets already carried, and now (re-deploy + org query) confirm,
     `readable=true editable=true` on `Task.`/`Event.` Is_Sequence_Call__c + Sequence_Step__c;
     `Login_Sequence_User` assigned to a Standard User test account and the fields confirmed
     reachable through that assignment (see R16). Blocker fully cleared; nothing outstanding.
2. **RESOLVED (2026-06-13) — CMDT records (R12, R13).** The prior `UNKNOWN_EXCEPTION`
   was NOT an org condition; it was a malformed-XML defect in the authored record
   files. Root cause: each record's `<value>` elements use the `xsd:` prefix
   (`xsi:type="xsd:double"`, `xsd:string`, `xsd:boolean`), but the root
   `<CustomMetadata>` element declared only `xmlns` and `xmlns:xsi` — the
   `xmlns:xsd="http://www.w3.org/2001/XMLSchema"` declaration was missing, leaving the
   prefix undeclared. Confirmed by diffing against the org-retrieved reference
   `Sequence_Step_Config.Step_1.md-meta.xml`. Fix: added the missing `xmlns:xsd`
   declaration to the root element of the other 13 files (Steps 2–10 + the 4
   Terminal_Status records); no field values, labels, or ordering changed. Re-deploy
   to `BlueSky` succeeded (14 records `Created`, errors: 0) and verification asserts
   pass (see R12/R13 above). Blocker cleared.
3. **R15 custom index on `Next_Action_Date__c`:** `CustomIndex` is generally not
   deployable via the Metadata API for most org editions and typically requires a
   Salesforce Support case. The metadata file
   `force-app/main/default/customIndexes/Target_Next_Action_Date.indx-meta.xml` is
   committed for traceability but excluded from the deploy manifest. Treat as an
   operational prerequisite for `04_scheduler_batch`, not a deployable artifact.

## Requirements traceability

- Satisfied + verified in org: R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13,
  R14, R16 (full FLS incl. the Task/Event cadence-field entries), R17.
- R9, R10: implemented on the `Activity` object (reflected to `Task` and `Event` via
  the standard Salesforce mechanism). FULLY VERIFIED on Task and Event (2026-06-13):
  `FieldDefinition` lists both fields on Activity/Task/Event; SOQL on Task/Event
  executes with no "No such column"; describe maps contain both fields and report
  `isAccessible()=true`. The reviewer's rejection was an FLS-visibility issue, now
  resolved via the perm-set FLS (R16) and validated by assigning `Login_Sequence_User`
  to a Standard User test account.
- Authored, deferred to Support per spec: R15 (custom index).
