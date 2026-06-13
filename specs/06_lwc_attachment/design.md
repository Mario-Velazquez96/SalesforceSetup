# Design — 06_lwc_attachment

**Source:** Target_Sequence_Solution_Design.md §7 (LWC), §3.6 (Files), §9; lwc conventions

## Approach

A small record-page LWC plus an `@AuraEnabled` controller. The component is a thin UI over
one field: it manages a single `ContentDocumentLink` on the `Target__c` and records the
selected `ContentDocumentId` in `Sequence_Attachment_Id__c`. The engine (02) does the
attaching at send time; this feature owns only the field + the linked file, so it depends
solely on `01_data_model`.

## Component layout

```
lwc/targetEmailAttachment/
  targetEmailAttachment.html        // lightning-file-upload, current-file row, Remove btn, spinner
  targetEmailAttachment.js          // @api recordId; @wire getCurrentAttachment; upload/remove handlers
  targetEmailAttachment.js-meta.xml // isExposed=true; target lightning__RecordPage (Target__c)
  __tests__/targetEmailAttachment.test.js
classes/
  SequenceAttachmentController.cls  // with sharing; getCurrentAttachment / setAttachment / removeAttachment
```

## UI behavior (R1–R6)

- `lightning-file-upload` with `record-id={recordId}` and `multiple=false` (single file, R2).
- `onuploadfinished` → take the uploaded `documentId`, call imperative
  `setAttachment({ recordId, contentDocumentId })`, then `refreshApex` the wire (R1).
- Current-file row rendered with `lwc:if` from the wire; **Remove** button → imperative
  `removeAttachment({ recordId })` (R3).
- `lightning-spinner` shown while any imperative call is in flight; `ShowToastEvent` for
  success/error; handlers `async/await` + `try/catch/finally` resetting loading in
  `finally` (R6). Event names lowercase; no `window.*`, no hardcoded Ids/labels (R6/R7).
- Empty state when no attachment (R5).

## Controller (R4, R7)

```apex
public with sharing class SequenceAttachmentController {
    @AuraEnabled(cacheable=true)
    public static AttachmentView getCurrentAttachment(Id recordId) { ... } // name + id from field
    @AuraEnabled
    public static void setAttachment(Id recordId, Id contentDocumentId) { ... } // replace prior, set field
    @AuraEnabled
    public static void removeAttachment(Id recordId) { ... }                    // clear field + unlink
}
```

- `setAttachment`: if `Sequence_Attachment_Id__c` already set and different, delete the
  prior sequence `ContentDocumentLink` (single-file enforcement, R2), then update the field
  to the new `ContentDocumentId`.
- All SOQL `WITH USER_MODE`; DML `AccessLevel.USER_MODE`; CRUD/FLS enforced; throws
  `AuraHandledException` on error (R7).
- Add `classAccesses` for `SequenceAttachmentController` to `Login_Sequence_User` (D2).

## Security (§9)

- `with sharing`; least-privilege; reps edit their own Targets. No widening of access.

## Test approach (§12, lwc conventions)

- **Jest** (`__tests__/targetEmailAttachment.test.js`): upload success (sets field, shows
  name), upload failure (toast, spinner cleared), single-file replacement, Remove → empty
  state, empty initial state. `afterEach` clears the DOM.
- **Apex** `SequenceAttachmentControllerTest`: `setAttachment` sets the field and removes a
  prior link; `removeAttachment` clears it; `getCurrentAttachment` returns name/id;
  negative (no access) path. Coverage target **>= 85%**.

## Open items / discrepancies

- None.
