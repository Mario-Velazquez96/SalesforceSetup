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
