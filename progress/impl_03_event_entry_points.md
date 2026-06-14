# Implementation Report — 03_event_entry_points

Status: COMPLETE — all tests green (45/45), per-feature-class coverage above the
85% target, deploy-validated (check-only) against the BlueSky sandbox. Awaiting
reviewer approval before the feature is marked `done`.

## Scope

Thin event capture over the `02` engine: start the cadence on `Target__c` insert
and set the next-action due date on sequence-call completion. NO batch, LWC, or
before-update terminal stop (those are 04/05/06). The engine
(`SequenceEngineService.processSteps`) is reused, not reimplemented.

## Environment

- Target org: `BlueSky` sandbox (`thomas@blueskyadvisory.com.inouvia`), API 67.0.
- `sf` invoked via `cmd //c "sf ... --target-org BlueSky --json"`; comma-bearing
  SOQL passed via `--file`. All temp scripts removed (scripts/ is empty).
- No `OrgWideEmailAddress` in the org; the engine degrades to running-user. No
  OWE added.
- Note: `sf project deploy start/validate` intermittently throws a CLI-side
  "Missing message metadata.transfer:Finalizing" finalize error AFTER the server
  job succeeds; confirmed each via `sf project deploy report --job-id ...`
  returning `Succeeded`, 0 component errors.

## Triggers and classes delivered

Under `force-app/main/default/`:

- `triggers/TargetTrigger.trigger` — **after insert only**; `switch on
  Trigger.operationType`; no business logic (R3). Structured so 05 can add an
  `AFTER_UPDATE`/`BEFORE_UPDATE` branch cleanly (one trigger per object).
- `triggers/TaskTrigger.trigger` — **after update**; routes to handler; no logic
  (R9). No prior Task trigger existed, so this is the single Task trigger.
- `classes/TargetTriggerHandler.cls` (`with sharing`) — `afterInsert(List<Target__c>)`
  enqueues `SequenceStartQueueable` with the Ids of newly inserted **active**
  Targets (R1). Static `Set<Id> processedInsertIds` recursion guard (R7).
- `classes/SequenceStartQueueable.cls` (`with sharing`, `Queueable`) — re-queries
  Targets via `TargetSelector.getByIds` (one SOQL, USER_MODE), builds
  `StepRequest`s with `stepToSend=1` for active Targets and calls
  `SequenceEngineService.processSteps` (R2, R8).
- `classes/TaskTriggerHandler.cls` (`with sharing`) — `afterUpdate(newTasks, oldMap)`:
  filters Tasks that transitioned into `Status='Completed'` with
  `Is_Sequence_Call__c=true` (R4/R5), one `TargetSelector.getByIds` query for the
  related Targets, and for each **active** Target whose `Sequence_Step__c` equals
  the Task's `Sequence_Step__c` sets `Next_Action_Date__c = now +
  Days_Until_Next_Email__c`; one `Database.update(..., USER_MODE)` with
  partial-success handling (R4, R6, R8). Static `Set<Id> processedTargetIds`
  recursion guard (R7). Does NOT send the next email (deferred to 04).
- Tests: `classes/TargetTriggerHandlerTest.cls`, `classes/TaskTriggerHandlerTest.cls`.

## Design note — active filtering at insert

`TargetTriggerHandler.afterInsert` takes `Trigger.new` (not just the Id set) and
enqueues only Targets that are `Sequence_Active__c=true` at insert. This is
consistent with R2/R6 (only active Targets start; the engine's own inactive guard
still applies defensively when the queueable re-queries) and means an inactive
insert does not auto-start. This was also necessary to keep the 02 dependency
tests deterministic (see cross-feature impact below).

## Requirements traceability (R1–R9)

| Req | Where satisfied | Verified by |
| --- | --- | --- |
| R1 | `TargetTriggerHandler.afterInsert` enqueues `SequenceStartQueueable` | `TargetTriggerHandlerTest.testActiveInsertStartsStep1`, `testBulk200ActiveInsert` |
| R2 | `SequenceStartQueueable.execute` → engine `processSteps(stepToSend=1)` for active | `testActiveInsertStartsStep1` (Email 1 + open Call 1 + completed Email + Sequence_Step__c=1), `testInactiveInsertDoesNothing` |
| R3 | `TargetTrigger` is the only `Target__c` trigger, no logic, `switch` to handler | trigger source; org query (one trigger) |
| R4 | `TaskTriggerHandler.afterUpdate` sets `Next_Action_Date__c = now + Days_Until_Next_Email__c` | `TaskTriggerHandlerTest.testMatchingCallCompleteSchedulesNextAction` (≈ now+4d, no email) |
| R5 | `Is_Sequence_Call__c != true` skipped | `testNonSequenceTaskCompleteDoesNothing` |
| R6 | inactive Target / step mismatch skipped | `testInactiveTargetDoesNothing`, `testStepMismatchDoesNothing` |
| R7 | static `Set<Id>` guards in BOTH handlers (not Boolean) | `TargetTriggerHandlerTest.testRecursionGuardSkipsAlreadyProcessedIds`, `TaskTriggerHandlerTest.testRecursionGuardSkipsAlreadyProcessed` |
| R8 | one SOQL + one DML per handler, 200-record safe | `TargetTriggerHandlerTest.testBulk200ActiveInsert`, `TaskTriggerHandlerTest.testBulk200CallCompletions` (asserts 1 SOQL + 1 Target DML for 200) |
| R9 | `TaskTrigger` is the only `Task` trigger, no logic, routes to handler | trigger source; org query (one trigger) |

Additional negative/edge coverage: non-Target `WhatId` ignored, already-Completed
update is not a transition (no re-schedule), null `Days_Until_Next_Email__c` →
waitDays 0, null/empty inputs no-op.

## One-trigger-per-object confirmation

Tooling-API query `SELECT Name, EntityDefinition.QualifiedApiName FROM ApexTrigger
WHERE EntityDefinition.QualifiedApiName IN ('Target__c','Task')` returned exactly
2 rows: `TargetTrigger -> Target__c`, `TaskTrigger -> Task`. Local repo has exactly
two `.trigger` files matching.

## Cross-feature impact (02 dependency tests — fixed, intent preserved)

Introducing the spec-mandated `TargetTrigger` (after-insert) changed automation
that the pre-existing 02 tests did not anticipate: those tests insert **active**
`Target__c` records in `@TestSetup`/in-test, which now starts the cadence and
created extra Call/Email tasks (and nulled `Next_Action_Date__c` at step 1),
breaking 8 of their assertions. To keep 02 green WITHOUT changing any 02
production code or assertion intent, the three 02 test classes now insert Targets
**inactive then activate via update** (the after-insert start branch does not fire
on update; persisted field values are identical):
- `SequenceEngineServiceTest` (`@TestSetup`, `testBulk200OneDmlPerObject`,
  `testMixedActiveInactiveBulk`)
- `SequenceSelectorsTest` (`@TestSetup`)
- `SequenceEmailServiceTest` (`@TestSetup`)

No 02 Apex logic was modified — only test fixtures. Flagging for the reviewer.

## Test results + per-class coverage

Command: `sf apex run test --target-org BlueSky --test-level RunSpecifiedTests
--tests TargetTriggerHandlerTest --tests TaskTriggerHandlerTest --tests
SequenceEngineServiceTest --tests SequenceEmailServiceTest --tests
SequenceSelectorsTest --code-coverage`.

- Outcome: **Passed — 45 / 45**, 0 failing.
- Per-feature-class coverage (03):
  - `TargetTriggerHandler` — 100% (12/12)
  - `SequenceStartQueueable` — 93% (14/15)
  - `TaskTriggerHandler` — 88% (45/51)
  - All three exceed the >= 85% target.
- Dependency classes still 96%: `SequenceEngineService` 96% (90/94),
  `SequenceEmailService` 96% (91/95).

### Org-wide coverage caveat (honest reporting)

Org-wide aggregate reads ~43–52% depending on the run, driven entirely by
pre-existing Salesforce-default sample classes (`TaskTargetController`,
`Communities*`, `SiteLogin/Register`, `ForgotPassword`, `ChangePassword`,
`MyProfilePageController`, etc.) that sit at 0% and are out of this feature's
scope. Every class this feature delivers is 88–100%. This is the same pre-existing
condition flagged by 02; it will matter for any future production `RunLocalTests`
deploy but cannot be remedied without editing out-of-scope code.

## Deploy validation

`sf project deploy validate --source-dir force-app/main/default/triggers
--source-dir force-app/main/default/classes --target-org BlueSky --test-level
RunSpecifiedTests --tests (the 5 above)` → `success: true`, `checkOnly: true`,
40 tests completed, 0 test errors, 0 component errors. Never deployed to
production. (Working copies were also deployed to the sandbox during iteration.)

## Manifest

`manifest/package.xml` updated: added `ApexTrigger` (TargetTrigger, TaskTrigger)
and the four new `ApexClass` members (TargetTriggerHandler, TaskTriggerHandler,
SequenceStartQueueable, + the two test classes).

## Repo cleanliness

All temp scripts removed; `scripts/` is empty. Working tree contains only feature
triggers/classes/tests, the manifest update, the 02 test-fixture edits, the
tasks.md checkmarks, and this report.

## Tasks

All `tasks.md` items 1–13 are now `[x]`.
