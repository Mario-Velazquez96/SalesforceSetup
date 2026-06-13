# Requirements — 06_lwc_attachment

**Feature:** Record-page LWC to attach a single file used on every sequence email
**Source:** Target_Sequence_Solution_Design.md §2 (Feature 12), §7 (LWC), §3.6, §9
**Depends on:** 01_data_model

## Purpose

Give reps a control on the `Target__c` record page to upload **one** file that the engine
attaches to every cadence email. The component writes the chosen `ContentDocumentId` to
`Sequence_Attachment_Id__c`; the engine (02) reads that field at send time. If no file is
attached, emails send with no attachment.

## In scope

- LWC `targetEmailAttachment` (record page on `Target__c`).
- `SequenceAttachmentController` (`@AuraEnabled` get / set / remove).

## Out of scope

- The engine's consumption of `Sequence_Attachment_Id__c` → already in `02_core_engine`
  (R5/R6 there). This feature only manages the field + linked file.

## Requirements (EARS)

**R1 (Event-driven):** When a user uploads a file via `targetEmailAttachment`, the system shall create a `ContentVersion` linked to the `Target__c` record and store its `ContentDocumentId` in `Sequence_Attachment_Id__c`.
**R2 (Ubiquitous):** The component shall accept **at most one** file; uploading a new file shall replace the prior sequence attachment (clear/relink so only one is referenced).
**R3 (Event-driven):** When a user clicks **Remove**, the system shall clear `Sequence_Attachment_Id__c` (and unlink the prior `ContentDocumentLink` for the sequence file).
**R4 (Ubiquitous):** `getCurrentAttachment` shall be `@AuraEnabled(cacheable=true)` and surfaced via `@wire` to display the current file name.
**R5 (State-driven):** While no file is attached, the component shall show an empty state (and, per 02, the engine sends with no attachment).
**R6 (Ubiquitous):** The component shall use `lightning-file-upload`, `lwc:if`, lowercase event names, a `lightning-spinner` during async work, and `ShowToastEvent` for success/error feedback; imperative Apex shall use `async/await` with `try/catch/finally`.
**R7 (Ubiquitous):** `SequenceAttachmentController` shall be `with sharing`, enforce CRUD/FLS, and use `WITH USER_MODE` SOQL / `AccessLevel.USER_MODE` DML; no hardcoded Ids/labels/URLs.

## Acceptance

- Uploading a file shows its name and sets `Sequence_Attachment_Id__c`; the next email
  carries it as an attachment (verified end-to-end with 02).
- Uploading a second file replaces the first (only one referenced).
- Remove clears the field and the next email sends with no attachment.
- Jest tests cover success, failure, single-file enforcement, and empty state.

## Open items

- None. (Single-file behavior and "no file = no attachment" are confirmed in the Solution
  Design §7.)
