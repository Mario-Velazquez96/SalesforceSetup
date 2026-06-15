# Session history (append-only)

## 01_data_model — completed 2026-06-13

Delivered (pure metadata foundation):
- Target__c custom fields R1–R8, including the Billing_City__c formula field.
- Task/Event cadence fields R9/R10, implemented on the shared Activity object so
  they reflect to both Task and Event.
- Sequence_Step_Config__mdt (+10 rows) and Sequence_Terminal_Status__mdt
  (+4 rows) — R11–R13.
- 10 Sequence_Email Lightning email templates — R14.
- Permission sets Login_Sequence_Admin and Login_Sequence_User with full FLS
  (incl. Task/Event cadence entries) — R16.
- API version 66.0 across the package — R17.

Notable issues resolved during implementation:
1. CMDT records (R12/R13) failed to deploy due to a missing xmlns:xsd
   declaration in the authored record files; fixed against the org-retrieved
   template and redeployed cleanly.
2. R9/R10 cadence fields initially appeared absent on Task/Event (first reviewer
   verdict REJECT). Root cause was the verifying user lacking FLS, not missing
   fields; resolved by granting readable/editable FLS on the Task/Event cadence
   entries in both permission sets, then confirming the fields queryable and
   describe-accessible.

R15 custom index — DROPPED (2026-06-13):
- The custom index on Target__c.Next_Action_Date__c (originally R15, deferred to a
  Salesforce Support case) was removed entirely by human decision. Feature 04's
  scheduler reads due targets via a Batch Apex start() QueryLocator, which is exempt
  from the "non-selective query against large object" exception, so no custom index is
  required for the query to run (it was only a performance optimization, and expected
  Target__c volume is modest). R15 was struck from the 01_data_model spec, the orphan
  index file (never deployed) was deleted, and feature 04's specs were reworded to drop
  the index dependency. No remaining Support-case prerequisite.

Result: all originally-deployed requirements satisfied; reviewer approved on re-review.
R15 subsequently removed from scope (see above) — no carried-forward operational items.

## 02_core_engine — completed 2026-06-13

Delivered (callable sequence core, unit/bulk tested in isolation):
- Selectors TargetSelector, TaskSelector, ContentSelector — inherited sharing,
  all queries WITH USER_MODE.
- SequenceStepConfigService — resolves Sequence_Step_Config__mdt per step.
- SequenceEmailService — template render, "RE:" subject prefix, attachment by
  ContentDocumentId, OrgWideEmailAddress resolved by name, plus @InvocableMethod
  entry point.
- SequenceEngineService — processStep + bulk processSteps with kill-switch guard,
  Call and Email task creation, step advance, and Next_Trigger_Type scheduling
  (Timer / CallCompleted / None). Bulkified to 1 DML per object, USER_MODE with
  partial-success handling.

Verification: 27/27 feature tests passing; SequenceEngineService 96% and
SequenceEmailService 96% coverage (both above the 95% target).

Carried notes:
- (a) Literal org-wide coverage ~52% is due ONLY to pre-existing out-of-scope
  Salesforce sample classes sitting at 0%; every 02_core_engine feature class is
  96–100%. Reviewer accepted this as non-blocking.
- (b) The BlueSky org has no OrgWideEmailAddress, so the engine resolves OWE by
  DisplayName and degrades gracefully to the running user when none exists —
  intended behavior per R3/R14, not a hardcoded fallback.

## 03_event_entry_points — completed 2026-06-13

Delivered (thin event capture over the engine):
- TargetTrigger (after-insert) + TargetTriggerHandler — enqueues
  SequenceStartQueueable, which runs engine step 1 on newly inserted active
  targets.
- TaskTrigger (after-update) + TaskTriggerHandler — when a sequence Call N
  completes on a matching active target, sets
  Next_Action_Date = now + Days_Until_Next_Email.
- One trigger per object, logic-free triggers delegating to handlers, static
  Set<Id> recursion guard, bulkified to 1 query / 1 DML per handler.

Verification: 45/45 feature tests passing; per-class coverage
TargetTriggerHandler 100%, SequenceStartQueueable 93%, TaskTriggerHandler 88%
(all >= 85%).

Carried notes:
- (a) The new after-insert TargetTrigger required test-only fixture changes in
  02's test classes (SequenceEngineServiceTest, SequenceSelectorsTest,
  SequenceEmailServiceTest) to insert-inactive-then-activate so the trigger does
  not perturb those tests. No 02 production logic changed; reviewer confirmed.
- (b) Stall behavior = leave paused (no fallback timer) for call-driven steps,
  and the next-email send remains deferred to 04_scheduler_batch.

## 04_scheduler_batch — completed 2026-06-13

Delivered (one scheduled job that drives all time-based progression):
- SequenceSchedulerBatch — `Database.Batchable<sObject>` + `Database.Stateful`.
  `start()` returns a `Database.QueryLocator` for active targets with
  `Next_Action_Date__c <= now` and `Sequence_Step__c < 10`, `WITH USER_MODE`
  (Batch QueryLocator, exempt from the selective-query rule — no custom index).
  `execute()` advances each due target through the engine to step+1 with one
  DML per object. `finish()` reports the stateful processed/error counts.
- SequenceSchedulerSchedulable — `Schedulable` that runs the batch at scope 200;
  CRON helper for every 8 hours `0 0 0,8,16 * * ?`.
- This single job realizes both the 4-day call waits (feature 03) and the
  14/7/14/14 email timers (feature 02).

Verification: 11/11 tests passing; per-class coverage SequenceSchedulerBatch 96%
and SequenceSchedulerSchedulable 100% (both above the >= 85% gate).

## 05_terminal_stop_and_guards — completed 2026-06-13

Delivered (terminal-stop guard added to the existing event entry points):
- Added a before-update branch to the EXISTING single TargetTrigger /
  TargetTriggerHandler from feature 03 — routed by `Trigger.operationType`, with
  NO second trigger created (one trigger per object preserved).
- On a Target whose `Status__c` changes to a terminal value while the sequence
  is active, the branch stamps `Sequence_Active__c = false`,
  `Sequence_Stop_Reason__c = `the matching
  `Sequence_Terminal_Status__mdt.Stop_Reason__c`, and `Next_Action_Date__c = null`
  directly on `Trigger.new` with NO extra DML.
- The terminal status set is metadata-driven from `Sequence_Terminal_Status__mdt`.
- Skips Targets whose status is unchanged and those already inactive; shares
  feature 03's static `Set<Id>` recursion guard.
- Confirmed both the manual kill switch and the automatic terminal kill switch
  halt the 03 (start/call) and 04 (scheduler) progression.

Verification: 26/26 feature tests passing; per-class coverage
TargetTriggerHandler 98% and TargetTrigger 100% (both above the >= 85% gate).

Carried note (R8 added mid-flight):
- The `Target__c.Status__c` RESTRICTED picklist originally lacked the 4 terminal
  values (Converted / Meeting Booked / Do Not Contact / Replied) referenced by
  `Sequence_Terminal_Status__mdt`, so the terminal-stop could never fire. Per
  human decision (2026-06-13) those 4 values were ADDED to the `Status__c` value
  set (deployed), while the CMDT terminal set was kept as exactly those 4 and the
  existing client statuses were left non-terminal. This was a data-model gap
  carried from feature 01, resolved within feature 05.

## 06_lwc_attachment — completed 2026-06-13

Delivered (rep-facing single-file upload UI; final feature — closes the loop with 02):
- LWC `targetEmailAttachment` on the `Target__c` record page — `lightning-file-upload`
  (single file), current-file row rendered via `lwc:if`, a Remove button,
  `lightning-spinner`, and `ShowToastEvent` toasts. Handlers use imperative Apex with
  `async/await` + `try/catch/finally` and call `refreshApex` after each mutation.
- `SequenceAttachmentController` (`with sharing`): `getCurrentAttachment` (cacheable,
  `@wire`); `setAttachment` stores the `ContentDocumentId` in `Sequence_Attachment_Id__c`
  with single-file replacement (deletes the prior link before repointing);
  `removeAttachment` clears the field and unlinks the prior `ContentDocumentLink`.
  CRUD/FLS enforced via `USER_MODE`.
- `SequenceAttachmentController` class access added to the `Login_Sequence_User`
  permission set.

Verification: 9/9 Apex tests passing with `SequenceAttachmentController` at 89% coverage
(>= 85% gate), and Jest 6/6 green (the only feature with a Jest suite).

Closes the loop with feature 02, whose engine already attaches
`Sequence_Attachment_Id__c` at send time.

## Bug fixes

- 2026-06-13: Sequence_Email_1 contact merge field changed from
  `{{{Primary_Contact__r.FirstName}}}` to `{{{Contact.FirstName}}}` and deployed
  to BlueSky (0 errors), bringing Email_1 in line with Sequence_Email_2..10.
  RENDER NOT VERIFIED — see open issue below.

### OPEN ISSUE (escalate): triple-brace HML does not resolve in these templates

Render verification via `Messaging.renderStoredEmailTemplate(templateId,
contactId, targetId)` did NOT resolve the merge field after the fix. Email_1
still rendered the LITERAL `Hi {{{Contact.FirstName}}},` (test Contact FirstName
= "D"). Critically, Sequence_Email_2 — assumed in the bug report to already
render correctly — ALSO rendered the literal `{{{Contact.FirstName}}},` under the
exact same call, so this is NOT an Email_1-specific outlier.

Root cause is a template-type/HML mismatch affecting ALL ten Sequence_Email
templates: their `-meta.xml` is `<type>custom</type>` / `<uiType>Aloha</uiType>`
(Classic Aloha), but the triple-brace `{{{...}}}` syntax is Lightning
(enhanced) email-template HML and does not resolve when a Classic `custom`
template is rendered via `renderStoredEmailTemplate`. The Email_1 field name is
now consistent with its siblings, but no Sequence_Email template currently
merges the recipient name at send time. Needs a leader/spec decision (convert
the templates to enhanced/Lightning type, or switch to Visualforce-style merge
fields valid for Aloha custom templates) before send-time personalization works.

### RESOLVED (2026-06-13): converted the 10 Sequence_Email templates Classic (Aloha) -> Lightning (SFX)

Per human decision (Option B), the 10 cadence templates were converted from
Classic (`type=custom` / `uiType=Aloha`) to Lightning (`uiType=SFX`,
`relatedEntityType=Contact`) so the triple-brace `{{{...}}}` HML resolves under
`Messaging.renderStoredEmailTemplate`.

Folder fix (the original 01 blocker "uiType=SFX + a classic EmailFolder did not
resolve the folder on deploy"): an SFX template CANNOT live in a Classic
`EmailFolder` (Folder `Type='Email'`) — deploy fails with
`Cannot find folder:Sequence_Emails`. Lightning templates require an ENHANCED
folder, which in metadata is a different type, `EmailTemplateFolder`
(`Type='EmailTemplate'`, with a `<folderShares>` block), NOT `EmailFolder`. The
pre-existing Classic `Sequence_Emails` folder could not be converted in place
(it kept `Type='Email'`), so the templates were moved to a NEW enhanced folder
`Sequence_Lightning_Emails` (`EmailTemplateFolder`). Template DeveloperNames are
unchanged (`Sequence_Email_1..10`), so `SequenceEmailService` still resolves them
by name — only `FolderName` changed, which the engine does not use. The 10 old
Aloha templates were first deleted via destructiveChanges (UiType cannot be
changed on an existing template: `You can set a UiType value only while creating
an email template`), then recreated fresh as SFX in the new folder.

Final WORKING merge-token form (determined EMPIRICALLY via a deployed probe
template rendered with `renderStoredEmailTemplate(tplId, contactId, targetId)`;
recipient = Contact via targetObjectId, related = Target__c via whatId):
- Contact first name: `{{{Recipient.FirstName}}}`
  (NOTE: `{{{Contact.FirstName}}}` THROWS
  `EMAIL_TEMPLATE_MERGEFIELD_ERROR: We don't recognize the field prefix Contact`
  under SFX — the old Aloha token is invalid for Lightning rendering.)
- Target name: `{{{Target__c.Name}}}`
- Target billing city: `{{{Target__c.Billing_City__c}}}` (the formula field that
  pulls `Company_Name__r.BillingCity`).
Applied consistently: all 10 bodies use `{{{Recipient.FirstName}}}`; all 10
subjects use `Interest in {{{Target__c.Name}}}`; Email_3 additionally uses
`{{{Target__c.Name}}}` + `{{{Target__c.Billing_City__c}}}` in its body. No
`Primary_Contact__r` traversal remains.

Render-verification result (real test data: Contact FirstName=Marcus,
Target Name=Riverside HVAC LLC, Billing City=Cleveland; temp records deleted):
- Email_1 subject -> `Interest in Riverside HVAC LLC`; greeting -> `Hi Marcus,`;
  no literal `{{{...}}}`.
- Email_3 greeting -> `Marcus,`; body -> `They view Riverside HVAC LLC as a
  top-tier platform in Cleveland`; both Target name and billing city resolved;
  no literal `{{{...}}}`.

Deploy: all 10 templates + the `Sequence_Lightning_Emails` EmailTemplateFolder
deployed to BlueSky with 0 errors. Send path re-verified: `SequenceEmailServiceTest`
11/11 passing, `SequenceEmailService` coverage 97% (>= 85% gate). The engine and
all Apex/trigger/LWC logic were left unchanged. The OPEN ISSUE above is now
resolved.

## Bug fix — 2026-06-13

Engine Tasks now assigned to the Target owner. Root cause: `TargetSelector`
did not query `Target__c.OwnerId` and `SequenceEngineService` omitted `OwnerId`
on both Task constructors, so Salesforce defaulted Task.OwnerId to the running
(system/automated) user when `SequenceSchedulerBatch` ran. Fix: added `OwnerId`
to the `TargetSelector` field list and set `Task.OwnerId = Target.OwnerId` on
both the open "Call N" task and the completed "Email N" task. Also added
`OwnerId` to the inline `SequenceSchedulerBatch.start()` query so the batch
feeds the engine a Target with its owner populated. A new
`SequenceEngineServiceTest` test creates a second active user, makes that user
the Target's owner, runs the engine, and asserts both created Tasks have
`OwnerId` == the Target owner and NOT the running user. All 48 tests across
SequenceEngineServiceTest / TargetTriggerHandlerTest / TaskTriggerHandlerTest /
SequenceSchedulerBatchTest pass; SequenceEngineService coverage 96% (>= 85%).

## Bug fix — 03_event_entry_points call-completion gating (2026-06-15)

Call-completion reschedule is now gated on the matched step's
`Sequence_Step_Config__mdt.Next_Trigger_Type__c == 'CallCompleted'`. The engine
creates a `Call N` task on every step, including Timer steps (6–9) where it has
already set `Next_Action_Date__c = now + Next_Wait_Days__c` (14/7/14/14).
Previously `TaskTriggerHandler.afterUpdate` rescheduled on ANY completed
sequence Call matching the target's step, so completing the Call on a Timer step
clobbered the engine-set 14-day timer with the 4-day call wait. Fix: the handler
reads the step-config map once (`SequenceStepConfigService.getByStep()`, one read,
still one DML) and only sets `Next_Action_Date__c = now + Days_Until_Next_Email__c`
when the matched step config's `Next_Trigger_Type__c == 'CallCompleted'`; Timer/None
steps (or a missing config) are a no-op so the engine-set wait governs. Existing
guards (R5 non-sequence, R6 inactive/step-mismatch, R7 recursion) unchanged.
Spec refined: R4 now requires `Next_Trigger_Type__c == 'CallCompleted'`; new R10
makes Timer/None steps a no-op on call completion. New test
`testTimerStepCallCompleteLeavesDateUnchanged` (step 6, Timer) seeds
`Next_Action_Date__c ≈ now+14` and asserts it is UNCHANGED after the matching
Call 6 completes (not overwritten with now + Days_Until_Next_Email). All 38 tests
across TaskTriggerHandlerTest / TargetTriggerHandlerTest / SequenceSchedulerBatchTest
pass (0 failures); TaskTriggerHandler coverage 89% (51/57 lines, >= 85%).
