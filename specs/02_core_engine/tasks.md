# Tasks — 02_core_engine

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [x] Build `TargetSelector`, `TaskSelector`, `ContentSelector` (`inherited sharing`, USER_MODE SOQL; `ContentSelector` returns latest `ContentVersion` by `ContentDocumentId`) (R2)
- [x] Build `SequenceStepConfigService` returning `Map<Integer, Sequence_Step_Config__mdt>` from `getAll()` (R1)
- [x] Build `SequenceEmailService.send(...)`: template render, `setTargetObjectId`/`setWhatId`, OWE address by name (R3, R14)
- [x] Apply `"RE: "` subject prefix when `Is_Reply__c` is true (R4)
- [x] Attach latest `ContentVersion` when `Sequence_Attachment_Id__c` is set; send with none when blank (R5, R6)
- [x] Add `SequenceEmailService` `@InvocableMethod` wrapper (label + description) delegating to `send` (R13)
- [x] Build `SequenceEngineService.processStep` + bulk `processSteps`: kill-switch guard, email, Call task, completed Email task, step advance (R7, R8)
- [x] Implement next-step scheduling by `Next_Trigger_Type__c`: Timer / CallCompleted / None (R9, R10, R11)
- [x] Enforce single DML per object + `Database.*` USER_MODE partial-success handling (R12)
- [x] Write `SequenceEmailServiceTest`: assert send (test context), RE: prefix, attachment present vs absent (R3–R6)
- [x] Write `SequenceEngineServiceTest`: positive (R8), each `Next_Trigger_Type__c` branch (R9–R11), inactive guard (R7)
- [x] Write 200-record bulk test: step advances on all, ≤1 DML/object, no governor errors (R12)
- [x] Write selector + config service tests (R1, R2)
- [x] Run tests; confirm **>= 95%** coverage on engine/email service; deploy-validate

## Verification

- **R7:** inactive `Target__c` → `processStep` yields 0 Tasks, 0 emails, unchanged fields.
- **R8:** active target, step 1 → 1 email (test context), `Call 1` open Task
  (`Is_Sequence_Call__c=true`, `ActivityDate = today+2`), 1 completed Email Task,
  `Sequence_Step__c=1`.
- **R9:** step 6 → `Next_Action_Date__c ≈ now + 14d`. **R10:** step 1 → `Next_Action_Date__c`
  is null. **R11:** step 10 → null, no further scheduling.
- **R4/R5/R6:** `Sequence_Email_2` send → subject starts `"RE: "`; with
  `Sequence_Attachment_Id__c` set, `setEntityAttachments` carries the file; blank → none.
- **R12:** 200-target bulk → `Limits.getDmlStatements()` shows one statement per object.

> Coverage target: **95%** for `SequenceEngineService` and `SequenceEmailService`.
