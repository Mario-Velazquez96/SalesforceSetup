# Implementation Report — 06_lwc_attachment

Status: COMPLETE — deployed to BlueSky, all 9 Apex tests green
(SequenceAttachmentController per-class coverage **89%**, >= 85% target), all 6
Jest tests green. Awaiting reviewer approval before the feature is marked `done`.

## Scope

Record-page LWC + Apex controller to manage the single file attached to every
cadence email. The component is a thin UI over `Target__c.Sequence_Attachment_Id__c`;
the engine (02) reads that field at send time. The engine was NOT touched.

## Environment notes

- CLI invoked as `cmd //c "sf ... --target-org BlueSky --json"`.
- `sf project deploy start` returned a CLI progress-bar localization error
  (`Missing message metadata.transfer:Finalizing`) but the deploy itself
  SUCCEEDED — confirmed via `sf project deploy report --job-id 0AfV900000CSnzlKAD`
  (all components `success: true`, status 0).
- Jest toolchain (`@salesforce/sfdx-lwc-jest`) was NOT present in `node_modules`;
  installed it with `npm install --no-save --legacy-peer-deps` (a pre-existing
  eslint peer-dep conflict required `--legacy-peer-deps`). Because of `--no-save`,
  `package.json`/`package-lock.json` were not modified. Jest then ran green.
- Two benign Jest warnings (not failures): `Invalid sourceApiVersion ... Expected
  58.0, found 66.0` (toolchain version note) and `registerApexTestWireAdapter is
  deprecated` (deprecation notice). Suite is 6/6 green.
- BlueSky org-wide Apex coverage is ~57% from out-of-scope sample classes; the
  in-scope class `SequenceAttachmentController` is **89%**.

## Files created / changed

Created:
- `force-app/main/default/classes/SequenceAttachmentController.cls` (+ `-meta.xml`)
- `force-app/main/default/classes/SequenceAttachmentControllerTest.cls` (+ `-meta.xml`)
- `force-app/main/default/lwc/targetEmailAttachment/targetEmailAttachment.js`
- `force-app/main/default/lwc/targetEmailAttachment/targetEmailAttachment.html`
- `force-app/main/default/lwc/targetEmailAttachment/targetEmailAttachment.js-meta.xml`
- `force-app/main/default/lwc/targetEmailAttachment/__tests__/targetEmailAttachment.test.js`
- `force-app/main/default/labels/CustomLabels.labels-meta.xml` (4 labels — used so
  the controller/LWC carry no hardcoded UI strings, R7)

Changed:
- `force-app/main/default/permissionsets/Login_Sequence_User.permissionset-meta.xml`
  — added `classAccesses` for `SequenceAttachmentController` (R7)
- `force-app/main/default/flexipages/Target_Record_Page.flexipage-meta.xml`
  — added `c:targetEmailAttachment` to the `main` region
- `manifest/package.xml` — added the 2 ApexClasses, the LightningComponentBundle,
  and the 4 CustomLabel members (FlexiPage + PermissionSet were already listed)
- `specs/06_lwc_attachment/tasks.md` — all items checked `[x]`

## Controller design (no engine change)

`public with sharing class SequenceAttachmentController`:
- `getCurrentAttachment(Id recordId)` `@AuraEnabled(cacheable=true)` → `AttachmentView`
  (`contentDocumentId`, `fileName`, `hasAttachment`); resolves the latest
  `ContentVersion` Title+FileExtension. Empty view when the field is blank or the
  doc is no longer visible.
- `setAttachment(Id recordId, Id contentDocumentId)` → if a different prior doc is
  stored, deletes the prior `ContentDocumentLink` for the record (single-file
  enforcement) then updates `Sequence_Attachment_Id__c`.
- `removeAttachment(Id recordId)` → unlinks the prior `ContentDocumentLink` and
  clears the field.
- All SOQL `WITH USER_MODE`; all DML `update/delete as user` (AccessLevel.USER_MODE);
  errors thrown as `AuraHandledException`; null-input guards. No hardcoded
  Ids/labels/URLs (validation message comes from a Custom Label).

## LWC behaviour

- `@api recordId`; `@wire(getCurrentAttachment, { recordId: '$recordId' })`.
- `lightning-file-upload` (single file, `multiple="false"`), shown only in the
  empty state; current-file row + `Remove` button shown via `lwc:if` when a file
  exists; `lightning-spinner` (`slds-is-relative` container) during async work.
- `onuploadfinished` → imperative `setAttachment` → `refreshApex` → success toast.
- `Remove` → imperative `removeAttachment` → `refreshApex` → success toast.
- Handlers are `async/await` with `try/catch/finally` (spinner reset in `finally`);
  `ShowToastEvent` for success/error; lowercase event names; empty state when no
  file (R5).

## Requirement → evidence traceability

- **R1** (upload stores ContentDocumentId): `setAttachment` writes the field;
  Apex `setAttachmentStoresDocumentId`; Jest "upload" test asserts the imperative
  call + payload.
- **R2** (at most one file; replace prior): `setAttachment` deletes the prior link
  before repointing; Apex `secondSetAttachmentReplacesPrior` (field replaced, prior
  link gone, new link kept); Jest single-file-replacement test.
- **R3** (Remove clears field + unlinks): `removeAttachment`; Apex
  `removeAttachmentClearsFieldAndUnlinks`; Jest remove test.
- **R4** (cacheable get via wire): `getCurrentAttachment(cacheable=true)` + `@wire`;
  Apex `getCurrentAttachmentReturnsCurrentFile`; Jest filled-state render test.
- **R5** (empty state): LWC `lwc:else` empty block; Apex
  `getCurrentAttachmentEmptyWhenNoFile`; Jest empty-initial + remove→empty tests.
- **R6** (file-upload, lwc:if, lowercase events, spinner, toasts, async/await
  try/catch/finally): LWC implementation; Jest success/failure tests assert toast
  variant and spinner cleared.
- **R7** (with sharing, CRUD/FLS, USER_MODE, AuraHandledException, no hardcoded
  Ids/labels, class access on perm set): controller security; Custom Labels;
  `classAccesses` entry; Apex `setAttachmentNullInputThrows`,
  `removeAttachmentNullInputThrows`, `noFieldAccessThrows` (Minimum Access user
  without FLS → exception).

## Test results

- Apex (`sf apex run test --tests SequenceAttachmentControllerTest --code-coverage`):
  **9/9 passed, 0 failed.** SequenceAttachmentController coverage **89%**.
- Jest (`npx sfdx-lwc-jest -- --testPathPattern targetEmailAttachment`):
  **6/6 passed** (1 suite). DOM reset + `jest.clearAllMocks()` in `afterEach`.

## Record-page note

The component was added to the existing `Target_Record_Page` flexipage (`main`
region) and deployed successfully, so no manual setup step is required for that
page. If the org later uses a different active Lightning page for `Target__c`, an
admin would drag "Sequence Email Attachment" onto it via the Lightning App Builder.

## Repo cleanliness

Temp files used to parse CLI JSON (`scripts/seqtest.*`) were deleted. No temp
scripts remain from this feature. `package.json` unchanged (Jest installed with
`--no-save`). The pre-existing `scripts/apex/schedule_sequence_scheduler.apex`
(from feature 03) was left untouched.

## Not done (by design)

- Feature is left `in_progress`; not marked `done` (reviewer gate).
- Engine (02) untouched.
