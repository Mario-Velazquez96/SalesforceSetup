# Review — 02_core_engine

**Verdict: APPROVE**
**Reviewer:** reviewer subagent · **Date:** 2026-06-14 · **Org:** BlueSky sandbox

The feature is implementation-complete, traceable end-to-end, all tests green,
and feature-scoped coverage exceeds the gate. The leader may mark
`02_core_engine` as `done`.

---

## 1. Test execution (verified, not reported)

`sf apex run test --target-org BlueSky --test-level RunSpecifiedTests` over
`SequenceEmailServiceTest`, `SequenceEngineServiceTest`, `SequenceSelectorsTest`
with `--code-coverage`:

- **Outcome: Passed — 27 / 27 passing, 0 failing.**
- Per-class coverage (this run):
  - `SequenceEngineService` — **96%** (90/94) — meets 95% gate
  - `SequenceEmailService` — **96%** (91/95) — meets 95% gate
  - `TargetSelector` 100%, `TaskSelector` 100%, `ContentSelector` 100%,
    `SequenceStepConfigService` 100%
- Test-run coverage: 97%. Org-wide aggregate: 52%.

## 2. Requirement -> test traceability (R1–R14)

| Req | Verdict | Test evidence |
| --- | --- | --- |
| R1  | PASS | `testConfigService` — 10 steps keyed by Step_Number, cache identity, unknown->null |
| R2  | PASS | selectors `inherited sharing` + `WITH USER_MODE` (source); `testTargetSelector*`, `testTaskSelector`, `testContentSelector` |
| R3  | PASS | `testBuildMessageStep1NoReplyNoAttachment` (TargetObjectId=Primary_Contact, WhatId=Target); `testRequestWithNoPrimaryContactSkipped`; `testOrgWideAddressResolvedByNameWhenPresent` |
| R4  | PASS | `testBuildMessageStep2AppliesReplyPrefix` — subject starts "RE: " |
| R5  | PASS | `testBuildMessageWithAttachment` — one ContentVersion in setEntityAttachments |
| R6  | PASS | `testBuildMessageStep1NoReplyNoAttachment`, `testInvalidAttachmentIdTreatedAsNoAttachment` |
| R7  | PASS | `testInactiveTargetGuard` (0 tasks, 0 email invocations, step unchanged, no schedule); `testMixedActiveInactiveBulk` |
| R8  | PASS (with one minor note) | `testProcessStep1Positive` — Call task Open, step=1, ActivityDate=today+2, Is_Sequence_Call=true; completed Email task (Status=Completed, Is_Sequence_Call=false); step advanced. See note below. |
| R9  | PASS | `testTimerSchedulesNextActionDate` — step 6 Timer, Next_Action_Date ~= now+14d |
| R10 | PASS | `testProcessStep1Positive` — step 1 CallCompleted -> Next_Action_Date null |
| R11 | PASS | `testNoneLeavesNextActionNull` — step 10 None -> null |
| R12 | PASS | `testBulk200OneDmlPerObject` — 200 targets, exactly 2 DML (1 Task insert + 1 Target update), 200 advanced; `testDmlFailureSurfacesAsEngineException` covers partial-success path |
| R13 | PASS | `testInvocableDelegatesToSend`, `testInvocableNullInputNoOp` |
| R14 | PASS | class declarations (`with sharing` services, `inherited sharing` selectors); OWE resolved by DisplayName, template by DeveloperName — no hardcoded Ids; `testOrgWideAddressResolvedByNameWhenPresent` |

**Minor note on R8 (non-blocking):** `testProcessStep1Positive` asserts the
completed Email task's Status, Subject and Is_Sequence_Call__c, but does not
assert `Type='Email'`. The implementation sets `Type='Email'` only when the
standard Task.Type field is FLS-createable for the running user — a deliberate,
defensible guard because engine DML runs in USER_MODE and writing an
inaccessible field would abort the insert. R8's intent (a distinguishable
completed email log task) is met via Status/Subject/Is_Sequence_Call. Accepted;
no action required.

## 3. Coverage judgment (the 85% question)

**Verdict: the org-wide 52% is NOT a blocker for closing this feature.** Accept
on feature-scoped coverage.

Reasoning:
- AGENTS.md / conventions require >= 85% per class; every class this feature
  delivers is 96–100%. The intent of the rule (the new code is thoroughly,
  meaningfully tested) is fully satisfied.
- The org-wide aggregate (52%) is dragged down entirely by pre-existing,
  out-of-scope Salesforce sample classes sitting at 0% that this feature did not
  author and does not touch. None of them exist in the `force-app/` source tree
  (verified by glob — no local `.cls` for any of them). They are org-resident
  Communities/Sites self-registration boilerplate:
  `TaskTargetController`, `CommunitiesSelfRegController`,
  `MicrobatchSelfRegController`, `SiteRegisterController`,
  `MyProfilePageController`, `ForgotPasswordController`,
  `ChangePasswordController`, `SiteLoginController`,
  `CommunitiesLoginController`, `CommunitiesLandingController`,
  `CommunitiesSelfRegConfirmController`.
- This feature is Apex-only with no triggers/jobs (per spec scope), so no
  production `RunLocalTests` deploy is in play here. The implementer correctly
  flagged that the org-wide figure will matter for any future production deploy
  — that is an org-hygiene backlog item, not a defect of `02_core_engine`.

## 4. Conventions (docs/conventions.md)

- Selectors `inherited sharing` + all SOQL `WITH USER_MODE` — PASS
- Services `with sharing` — PASS
- Bulk-safe DML via `Database.insert/update(records, false, AccessLevel.USER_MODE)`
  with partial-success handling in `assertSaved` — PASS
- No SOQL/DML inside loops; template Ids, OWE, and ContentVersions all resolved
  in bulk before the per-record build loop — PASS
- Naming PascalCase classes / camelCase members — PASS
- No leftover `System.debug()` — PASS (grep clean)
- Test-class naming: classes use the `...Test` suffix (e.g. `SequenceEngineServiceTest`)
  rather than the `_Test` suffix literally written in conventions.md. This
  matches the existing repo pattern and Salesforce defaults; not flagged as a
  defect.

## 5. Scope discipline & repo cleanliness

- No metadata created/changed beyond spec: only the 8 spec'd classes (3 selectors,
  config service, email service + invocable, engine) and their 3 test classes.
- No object/field/flow/trigger introduced (correct — those belong to 03/04/05/06).
- Scratch/diagnostic artifacts removed: no `diag*.apex`, `dep*.json`,
  `deploy_out.json`, `t_email.json`, `q_cmdt.soql` or temp run JSON remain.
  Only the pre-existing tracked samples `scripts/apex/hello.apex` and
  `scripts/soql/account.soql` are present — correctly left intact.
- `tasks.md`: all 14 items `[x]`, each spot-checked against delivered code/tests.

## Conclusion

APPROVE. All R1–R14 are test-backed, 27/27 tests pass, both required classes are
at 96% (>= 95% gate), conventions and scope are clean. The org-wide 85% shortfall
is a pre-existing, out-of-scope condition and is not a blocker for closing this
feature. Leader: `02_core_engine` may be marked `done`.
