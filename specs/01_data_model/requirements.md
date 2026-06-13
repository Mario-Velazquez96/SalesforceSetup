# Requirements — 01_data_model

**Feature:** Data model — fields, Custom Metadata Types + rows, email templates, permission sets
**Source:** Target_Sequence_Solution_Design.md §3 (Data Model), §3.5 (Email Templates), §9 (Security), §1 (standards)
**Depends on:** none (foundation layer)

## Purpose

Establish all declarative metadata the cadence engine depends on: custom fields on
`Target__c` and `Task`, two Custom Metadata Types with their seed rows, 10 Lightning
Email Templates, and the permission sets. This feature contains **no
business logic** — every later feature depends on it.

## In scope

- `Target__c` fields: `Sequence_Active__c`, `Sequence_Step__c`, `Days_Until_Next_Email__c`,
  `Sequence_Stop_Reason__c`, `Next_Action_Date__c`, `Primary_Contact__c`,
  `Sequence_Attachment_Id__c`, `Billing_City__c` (formula).
- `Task` fields: `Is_Sequence_Call__c`, `Sequence_Step__c`.
- `Sequence_Step_Config__mdt` (CMDT) + 10 rows (steps 1–10).
- `Sequence_Terminal_Status__mdt` (CMDT) + 4 rows.
- 10 Lightning Email Templates `Sequence_Email_1..10`.
- Permission sets `Login_Sequence_Admin`, `Login_Sequence_User` (FLS for the new fields).

## Out of scope

- All Apex (`02_core_engine`+), triggers (`03`/`05`), batch (`04`), and LWC (`06`).
- Apex class access entries on `Login_Sequence_User` — added by the features that
  introduce the classes (cite this feature as the FLS owner).

## Requirements (EARS)

**R1 (Ubiquitous):** The system shall provide on `Target__c` the field `Sequence_Active__c` (Checkbox, default **true**).
**R2 (Ubiquitous):** The system shall provide on `Target__c` the field `Sequence_Step__c` (Number(2,0), default **0**).
**R3 (Ubiquitous):** The system shall provide on `Target__c` the field `Days_Until_Next_Email__c` (Number(3,0), default **4**).
**R4 (Ubiquitous):** The system shall provide on `Target__c` the field `Sequence_Stop_Reason__c` (Text(255)).
**R5 (Ubiquitous):** The system shall provide on `Target__c` the field `Next_Action_Date__c` (DateTime).
**R6 (Ubiquitous):** The system shall provide on `Target__c` the field `Primary_Contact__c` (Lookup to `Contact`).
**R7 (Ubiquitous):** The system shall provide on `Target__c` the field `Sequence_Attachment_Id__c` (Text(18)).
**R8 (Ubiquitous):** The system shall provide on `Target__c` the field `Billing_City__c` as a Text **formula** equal to `Company_Name__r.BillingCity`.
**R9 (Ubiquitous):** The system shall provide on `Task` the field `Is_Sequence_Call__c` (Checkbox).
**R10 (Ubiquitous):** The system shall provide on `Task` the field `Sequence_Step__c` (Number(2,0)).
**R11 (Ubiquitous):** The system shall provide the Custom Metadata Type `Sequence_Step_Config__mdt` with fields `Step_Number__c` (Number), `Email_Template_Dev_Name__c` (Text), `Is_Reply__c` (Checkbox), `Call_Task_Subject__c` (Text), `Call_Due_Offset_Days__c` (Number), `Next_Trigger_Type__c` (Text/Picklist: `CallCompleted`/`Timer`/`None`), `Next_Wait_Days__c` (Number).
**R12 (Ubiquitous):** The system shall provide 10 rows in `Sequence_Step_Config__mdt` for steps 1–10 per the table in Design §Rows, where steps 1–5 use `Next_Trigger_Type__c='CallCompleted'`, steps 6–9 use `Timer` with `Next_Wait_Days__c` = 14/7/14/14, step 10 uses `None`, and `Is_Reply__c=true` for steps 2–10.
**R13 (Ubiquitous):** The system shall provide the Custom Metadata Type `Sequence_Terminal_Status__mdt` with fields `Status_Value__c` (Text) and `Stop_Reason__c` (Text), and rows for `Converted`, `Meeting Booked`, `Do Not Contact`, `Replied`.
**R14 (Ubiquitous):** The system shall provide 10 Lightning Email Templates `Sequence_Email_1..10` whose merge fields resolve `[Target Name]`→`{{{Target__c.Name}}}`, `[Primary Contact]`→`{{{Contact.FirstName}}}`, `[Billing City]`→`{{{Target__c.Billing_City__c}}}`.
~~R15 — REMOVED 2026-06-13: custom index dropped; see resolved decisions.~~
**R16 (Ubiquitous):** The system shall provide permission sets `Login_Sequence_Admin` (manage the CMDTs) and `Login_Sequence_User` (FLS read/edit on all new `Target__c` and `Task` fields).
**R17 (Ubiquitous):** All new metadata shall use API version **66.0**.

## Acceptance

- All fields deploy to a scratch/sandbox org and appear on `Target__c`/`Task`.
- `Sequence_Step_Config__mdt.getAll()` returns 10 rows with the values in Design §Rows;
  `Sequence_Terminal_Status__mdt.getAll()` returns 4 rows.
- Each `Sequence_Email_1..10` renders with the three merge fields populated from a sample
  Target + Contact.
- A user with `Login_Sequence_User` can read/edit the new fields.

## Resolved decisions (approval gate, 2026-06-12)

- **`Company_Name__c` targets `Account`** (confirmed) — `Billing_City__c =
  Company_Name__r.BillingCity` (R8). Was Solution Design §10 item 4.

### Resolved decisions (2026-06-13)

- **Custom index on `Target__c.Next_Action_Date__c` DROPPED (former R15).** The scheduler
  (feature 04) reads due targets via a Batch Apex `Database.getQueryLocator` in `start()`.
  Batch `start()` QueryLocators are exempt from the "non-selective query against a large
  object" exception, so the query runs without a custom index — the index was only a
  performance optimization, not a correctness requirement. The org also expects modest
  `Target__c` volume. The custom index, and its Salesforce Support-case prerequisite, are
  therefore removed from scope. R16/R17 numbering is intentionally left unchanged.

## Open items

- None.
