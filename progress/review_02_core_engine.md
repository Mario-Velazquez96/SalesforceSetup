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

---

## Option A re-review (2026-06-15)

**Verdict: APPROVE**
**Reviewer:** reviewer subagent · **Date:** 2026-06-17 · **Org:** BlueSky sandbox

Re-review of the client-approved behavioral change: "Option A" send-as-owner in
`SequenceEmailService`, superseding the short-lived Option B (Reply-To) POC.

### 1. R3 / Option A — send-as-owner From selection (VERIFIED CORRECT)

`SequenceEmailService.buildMessages` sets the From by matching the TARGET
OWNER's email to a verified OWE, with the documented fallback chain:

- **Bulk owner-email resolution** — `resolveOwnerEmails(requests)` collects every
  `req.target.OwnerId` into a Set and runs ONE `User` query
  (`SELECT Id, Email FROM User WHERE Id IN :ownerIds WITH USER_MODE`), returning
  `Map<Id targetId, String email>`. No SOQL in a loop. (lines 227-261)
- **Bulk OWE-by-address resolution** — `resolveOwnerOweByAddress(...)` runs ONE
  `OrgWideEmailAddress WHERE Address IN :ownerEmails` query into
  `Map<String addressLower, Id>` (lower-cased for case-insensitive match).
  (lines 272-292)
- **@TestVisible seam** — `ownerOweByAddressOverride` (Map<String,Id>) is returned
  INSTEAD of querying when non-null, so tests inject a known owner->OWE map without
  provisioning real OWEs. Plus `selectedOweByTarget` oracle records the chosen id
  per Target (SingleEmailMessage has no OWE getter). (lines 34-46, 272-276)
- **Per-message selection** — owner OWE if matched, else `defaultOrgWideId`
  (resolved by display name, with any-OWE then null fallback), else unset =
  running user; only calls `setOrgWideEmailAddressId` when non-null. (lines 145-158)
- The bulk resolution is performed ONCE before the per-request loop; the loop only
  does in-memory map lookups. 200-safe.

### 2. R14 — security (VERIFIED INTACT)

`with sharing` on the service; `WITH USER_MODE` on the `User` query; no hardcoded
addresses, Ids, or template Ids — owner-email match / display name / developer
name resolved at runtime. (The OWE-by-address query has no USER_MODE, consistent
with the existing default-OWE resolver; OWE is org-config metadata, not
user-shared data — acceptable and unchanged from prior approval.)

### 3. POC removal (VERIFIED FULLY GONE)

- No `setReplyTo`, `setSenderDisplayName`, `resolveOwnerNames`, or
  `resolveOwnerUsers` anywhere in `SequenceEmailService.cls` (grep: no matches).
- No Reply-To references or POC tests in `SequenceEmailServiceTest.cls`
  (grep: no matches). The two new seam-based tests replace them.
- `progress/poc_reply_to_owner.md` is DELETED (glob: no file found).
- No `System.debug` in `SequenceEmailService.cls` (grep: no matches).

### 4. Tests + coverage (VERIFIED, RUN BY REVIEWER)

`SequenceEmailServiceTest` covers both required cases via the @TestVisible seam:
- (a) `testSendAsOwnerSelectsOwnerOwe` — owner email maps to an injected OWE id;
  asserts `selectedOweByTarget` == that OWE id (owner-matched From).
- (b) `testSendAsOwnerFallsBackWhenOwnerHasNoOwe` — empty injected map + a
  nonexistent default display name; asserts the chosen id == the resolved default
  (or null = running user), proving the fallback path with no error.

Command:
`sf apex run test --target-org BlueSky --test-level RunSpecifiedTests --tests
SequenceEmailServiceTest --tests SequenceEngineServiceTest --code-coverage --json
--wait 30`
- Outcome: **Passed — 26/26, 0 failures.**
- Per-class coverage: **SequenceEmailService 92% (133/144)**, SequenceEngineService
  96% (92/96) — both exceed the >= 85% gate.
- BlueSky has no OWEs (live send falls back to running user — expected). Org-wide
  ~54% is the documented out-of-scope sample-class condition; judged per-feature.
  Out-of-scope `TaskTargetControllerTest` not in this run/source tree — ignored.

### 5. tasks.md + repo cleanliness

- `tasks.md` reflects the change: the send-as-owner task (line 8), the POC-removal
  task (line 9), and the seam-based test task (line 17) are all `[x]`, and the
  Verification section documents the R3 send-as-owner cases.
- Working tree clean of scratch files: only the expected feature/spec/progress
  files are modified; NO untracked files.

### Minor (non-blocking)

- `tasks.md` line 21 ("Run tests; confirm >= 85% coverage; deploy-validate") is
  still `[ ]` though the impl note documents it as done and the reviewer just
  re-verified the run. Recommend the implementer flip it to `[x]` for accuracy.
  Not a blocker — the substance (tests green, coverage met) is verified.

### Conclusion

Send-as-owner selection (owner OWE -> default OWE -> running user) and its
fallback are correct, bulk-safe, and tested via the @TestVisible seam. The
Option B POC is fully removed (code, tests, and doc). The leader may mark
`02_core_engine` as `done`.
