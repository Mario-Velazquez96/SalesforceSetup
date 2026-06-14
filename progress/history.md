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
