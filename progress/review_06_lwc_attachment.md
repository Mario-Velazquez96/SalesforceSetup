# Review — 06_lwc_attachment

**Verdict: APPROVE**

The final feature `06_lwc_attachment` is complete, deployed, and verified against
its spec. The leader may mark this feature `done`.

## 1. Requirement → test traceability (R1–R7)

| Req | Evidence | Status |
|-----|----------|--------|
| **R1** upload creates ContentVersion link + stores ContentDocumentId in `Sequence_Attachment_Id__c` | Apex `setAttachmentStoresDocumentId` asserts field == docId; Jest "calls setAttachment…on upload" asserts imperative payload `{recordId, contentDocumentId}` | PASS |
| **R2** at most one file; new upload replaces prior | `setAttachment` deletes prior `ContentDocumentLink` before repointing; Apex `secondSetAttachmentReplacesPrior` asserts field repointed, prior link count 0, new link count 1; Jest single-file-replacement test | PASS |
| **R3** Remove clears field + unlinks prior link | `removeAttachment`; Apex `removeAttachmentClearsFieldAndUnlinks` (field null + link count 0); Jest remove test | PASS |
| **R4** `getCurrentAttachment` cacheable + wired | `@AuraEnabled(cacheable=true)` on controller; `@wire` in JS; Apex `getCurrentAttachmentReturnsCurrentFile`; Jest filled-state render test | PASS |
| **R5** empty state when no file | HTML `lwc:else` empty block + uploader; Apex `getCurrentAttachmentEmptyWhenNoFile`; Jest empty-initial + remove→empty | PASS |
| **R6** LWC conventions | `lightning-file-upload` (multiple=false), `lwc:if`/`lwc:else`, lowercase `onuploadfinished`/`onclick`, `lightning-spinner` gated on `isLoading`, `ShowToastEvent`; handlers `async/await` + `try/catch/finally` with spinner reset in `finally`; `refreshApex` after each mutation; Jest success/failure assert toast variant + spinner cleared | PASS |
| **R7** controller security | `public with sharing`; all SOQL `WITH USER_MODE`; all DML `update/delete as user` (AccessLevel.USER_MODE); `AuraHandledException` on error; null-input guards; UI strings via Custom Labels (no hardcoded labels/Ids/URLs); class access on perm set; Apex `setAttachmentNullInputThrows`, `removeAttachmentNullInputThrows`, `noFieldAccessThrows` (Minimum Access user denied) | PASS |

No requirement lacks test evidence.

## 2. Apex tests (ran)

`sf apex run test --tests SequenceAttachmentControllerTest --code-coverage`:
- **9/9 passed, 0 failed** (testRunId 707V90000GcqgCD, 100% pass rate).
- **SequenceAttachmentController per-class coverage: 89%** — meets the >= 85% gate.
- Org-wide 57% is from pre-existing out-of-scope sample classes (not in scope).

## 3. Jest (ran-and-passed)

`npx sfdx-lwc-jest -- --testPathPattern targetEmailAttachment`:
- **6/6 passed, 1 suite.** Covers empty initial render (R5), filled render (R4),
  upload success (R1/R6), upload failure → error toast + spinner cleared (R6),
  single-file replacement (R2), remove → empty (R3/R5).
- `afterEach` removes all DOM children + `jest.clearAllMocks()`; wire mocked via
  `registerApexTestWireAdapter`; imperative Apex + `refreshApex` mocked.
- Two benign warnings only (not failures): `Invalid sourceApiVersion Expected 58.0,
  found 66.0` (toolchain note) and `registerApexTestWireAdapter is deprecated`.

## 4. js-meta.xml + wiring

- `isExposed=true`; single target `lightning__RecordPage`; `targetConfig` scoped
  to `<object>Target__c</object>`. Correct.
- `SequenceAttachmentController` class access added to `Login_Sequence_User`
  permission set (`classAccesses`, enabled=true). Confirmed.
- Component added to `Target_Record_Page` flexipage (`main` region,
  `c:targetEmailAttachment`) — no manual setup step required for that page.

## 5. Conventions & scope

- No SOQL/DML in loops; all queries `WITH USER_MODE`, all DML `as user`.
- FLS/CRUD enforcement is real (USER_MODE), not cosmetic — proven by the
  `noFieldAccessThrows` negative test.
- No `System.debug()` in the controller.
- `tasks.md` fully `[x]`.
- package.xml updated (2 ApexClasses, LWC bundle, 4 Custom Labels).
- Repo clean: only feature-03's pre-existing `scripts/apex/schedule_sequence_scheduler.apex`
  remains; no scratch/diagnostic files from this feature.

## Verified deliverables
- `force-app/main/default/classes/SequenceAttachmentController.cls`
- `force-app/main/default/classes/SequenceAttachmentControllerTest.cls`
- `force-app/main/default/lwc/targetEmailAttachment/*` (+ `__tests__`)
- `force-app/main/default/labels/CustomLabels.labels-meta.xml`
- `force-app/main/default/permissionsets/Login_Sequence_User.permissionset-meta.xml`
- `force-app/main/default/flexipages/Target_Record_Page.flexipage-meta.xml`

**Recommendation: APPROVE. The leader may mark `06_lwc_attachment` as `done`.**
