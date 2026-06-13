# Tasks — 01_data_model

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [x] Confirmed: `Company_Name__c` targets `Account` → `Billing_City__c = Company_Name__r.BillingCity` (R8)
- [x] Create `Target__c` fields: `Sequence_Active__c`, `Sequence_Step__c`, `Days_Until_Next_Email__c`, `Sequence_Stop_Reason__c`, `Next_Action_Date__c`, `Primary_Contact__c`, `Sequence_Attachment_Id__c` (R1–R7) — `Primary_Contact__c` pre-existed and matches spec; all deployed and verified in org
- [x] Create `Target__c.Billing_City__c` formula = `Company_Name__r.BillingCity` (R8) — deployed and verified
- [x] Create the two cadence activity fields `Is_Sequence_Call__c`, `Sequence_Step__c` (R9, R10) on the **`Activity`** object (reflects to Task and Event — the supported Salesforce mechanism; they cannot be created on `Task` directly, which caused the original "bad value for restricted picklist field: Task" error). DEPLOYED to `Activity` (Created, errors: 0) and **verified end-to-end on Task and Event (2026-06-13)**: `SELECT Id, Is_Sequence_Call__c, Sequence_Step__c FROM Task LIMIT 1` and the `Event` equivalent both execute with NO "No such column"; global describe field maps for Task and Event contain both fields and report `isAccessible()=true`. The earlier reviewer failure was an FLS-visibility issue, not a missing field — resolved by the `Login_Sequence_User`/`Login_Sequence_Admin` FLS (see report R9/R10 + R16).
- [x] Create CMDT `Sequence_Step_Config__mdt` with the 7 fields (R11) — deployed and verified
- [x] Load the 10 step rows per Design §Rows table (R12) — deployed and verified (10 records in org; `getAll().size()=10`, Step_6 spot-check passed)
- [x] Create CMDT `Sequence_Terminal_Status__mdt` with its 2 fields (R13) — deployed and verified
- [x] Load the 4 terminal-status rows (R13) — deployed and verified (4 records in org; `getAll().size()=4`)
- [x] Build 10 Lightning Email Templates `Sequence_Email_1..10` from `project-documents/client_requirement.md` copy with the three merge fields (R14) — deployed and verified (10 templates in org)
- ~~Request/create the custom index on `Next_Action_Date__c` (former R15)~~ — REMOVED 2026-06-13: custom index dropped (batch `start()` QueryLocator is exempt from the non-selective-query limit; modest volume). See requirements §Resolved decisions (2026-06-13).
- [x] Create permission sets `Login_Sequence_Admin` and `Login_Sequence_User` with FLS for all new fields (R16) — deployed/validated; cadence FLS (`Task.`/`Event.` Is_Sequence_Call__c + Sequence_Step__c) confirmed `readable=true editable=true` in the org on both perm sets; `Login_Sequence_User` assigned to a Standard User (Gabriel Silva) and the four cadence fields confirmed reachable through that assignment
- [x] Set API version 66.0 on all new metadata (R17) — `sourceApiVersion` 66.0; all deploys used v66.0
- [x] Deploy-validate to scratch/sandbox; run the data checks below — done against sandbox `BlueSky`; results in report

## Verification

- **R1–R8:** deploy succeeds; fields visible on `Target__c`; defaults correct
  (`Sequence_Active__c=true`, `Sequence_Step__c=0`, `Days_Until_Next_Email__c=4`).
- **R9–R10:** the two fields live on the `Activity` object and reflect to Task/Event;
  deploy to `Activity` succeeds. (Activity-reflected fields are referenced for FLS as
  `Task.<field>` and `Event.<field>` — see report.)
- **R11–R13 (anonymous Apex):**
  `Assert.areEqual(10, Sequence_Step_Config__mdt.getAll().size());`
  spot-check Step_6 → `Timer`, `Next_Wait_Days__c=14`, `Is_Reply__c=true`;
  `Assert.areEqual(4, Sequence_Terminal_Status__mdt.getAll().size());`
- **R14:** render `Sequence_Email_3` against a sample Target (with `Company_Name__c`→Account
  having a Billing City) + Contact → `[Target Name]`, `[Primary Contact]`, `[Billing City]`
  all resolve.
- **R16:** assign `Login_Sequence_User` to a test user; confirm field read/edit access.

> No Apex coverage applies (declarative-only feature).
