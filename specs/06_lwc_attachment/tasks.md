# Tasks — 06_lwc_attachment

> Each task cites the requirement(s) it satisfies. Mark `[x]` as completed.

- [ ] Build `SequenceAttachmentController` (`with sharing`): `getCurrentAttachment` (cacheable), `setAttachment`, `removeAttachment` (R4, R7)
- [ ] `setAttachment`: store `ContentDocumentId` in `Sequence_Attachment_Id__c`, removing any prior sequence link (single file) (R1, R2)
- [ ] `removeAttachment`: clear the field + unlink the prior `ContentDocumentLink` (R3)
- [ ] Enforce CRUD/FLS, USER_MODE SOQL/DML, `AuraHandledException` on error (R7)
- [ ] Build `targetEmailAttachment` LWC: `lightning-file-upload` (single), current-file row via `lwc:if`, Remove button, spinner, toasts (R5, R6)
- [ ] Wire `getCurrentAttachment`; imperative `setAttachment`/`removeAttachment` with `async/await` + `try/catch/finally` + `refreshApex` (R1, R3, R4, R6)
- [ ] Configure `js-meta.xml`: `isExposed=true`, `lightning__RecordPage` target scoped to `Target__c`; add to the record page (R6)
- [ ] Add `SequenceAttachmentController` class access to `Login_Sequence_User` (R7)
- [ ] Write Jest tests: upload success, upload failure, single-file replacement, remove → empty, empty initial (R1, R2, R3, R5)
- [ ] Write `SequenceAttachmentControllerTest`: set/remove/get + negative access (R1, R3, R4, R7)
- [ ] Run Apex + Jest; confirm **>= 85%** coverage; deploy-validate

## Verification

- **R1/R2:** upload a file → name shows, `Sequence_Attachment_Id__c` set; upload a second
  → replaces the first (only one `ContentDocumentLink` for the sequence file).
- **R3/R5:** Remove → field cleared, empty state shown.
- **End-to-end with 02:** with a file attached, the next sequence email carries it; after
  Remove, the next email sends with none (Solution Design §12 step 4).
- **Jest:** success/failure/single-file/empty all green; DOM reset in `afterEach`.

> Coverage target: **>= 85%** (Apex controller) + green Jest suite.
