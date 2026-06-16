---
name: salesforce-org-gotchas
description: Non-obvious Salesforce metadata/org gotchas hit while deploying the cadence data model to the BlueSky sandbox
metadata:
  type: project
---

Three deploy gotchas confirmed in the BlueSky sandbox during feature 01_data_model:

1. **Task/Event custom fields must be created on the `Activity` object, not `Task`.** Deploying a field under `objects/Task/fields/` fails with `bad value for restricted picklist field: Task`. Put it under `objects/Activity/fields/` — Salesforce reflects Activity custom fields onto both Task and Event automatically. In package.xml reference them as `Activity.<field>`. Relevant to 03/05, which read these cadence fields on Task.

2. **Reflected Activity fields can look "absent" on Task/Event purely due to FLS.** A user without field-level security on the field gets `No such column` in SOQL and the field missing from the describe map — this mimics a reflection/propagation failure but is just FLS. Fix is to grant `readable=true` (and `editable`) in the permission set, referencing the field via the child object (`Task.<field>` / `Event.<field>`, never `Activity.<field>`).

3. **CustomMetadata record files need `xmlns:xsd` declared on the root element.** The `<value>` elements use `xsi:type="xsd:double|string|boolean"`; if the root `<CustomMetadata>` declares only `xmlns` and `xmlns:xsi` (missing `xmlns:xsd="http://www.w3.org/2001/XMLSchema"`), the deploy fails with a platform `UNKNOWN_EXCEPTION`. Retrieving a record from the org gives the correct, normalized template (fields alphabetized — ordering is cosmetic).

4. **CMDT/config that references picklist values must match the actual restricted value set (found in 05).** `Sequence_Terminal_Status__mdt` listed Converted/Meeting Booked/Do Not Contact/Replied, but `Target__c.Status__c` is a RESTRICTED picklist whose real values were different (Not Cleared/Conflicted/In-Process/.../Closed) — so updating Status__c to a terminal value threw `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` and the terminal-stop branch could never fire. Resolution: first the 4 values were added to the Status__c `valueSetDefinition`, but the CLIENT later reverted that (2026-06-15) — the terminal set now reuses EXISTING Status__c values (Closed, Target Not Interested, Client Not Interested, Conflicted) and the CMDT rows map to those. Lesson: when config/CMDT enumerates picklist values, verify they exist in the restricted value set before building logic that sets them — and prefer mapping to the client's existing values over inventing new ones.

5. **HML `{{{...}}}` merge fields only resolve in LIGHTNING email templates, not Classic (found post-06).** The 10 cadence templates were deployed Classic (`type=custom`, `uiType=Aloha`) but used Handlebars `{{{Object.Field}}}` syntax, so on a real send every merge field rendered as literal text — Classic templates use Visualforce `{!Object.Field}` instead. Fix (human chose convert-to-Lightning): made them `uiType=SFX` Lightning templates in an ENHANCED `EmailTemplateFolder` (a classic EmailFolder will NOT resolve SFX templates on deploy — this was the blocker that originally pushed them to Classic), with `relatedEntityType` set. The working tokens for the engine's `renderStoredEmailTemplate(templateId, ContactId, TargetId)` send (recipient=Contact via setTargetObjectId, related=Target__c via setWhatId) are: contact name = `{{{Recipient.FirstName}}}` (NOT `{{{Contact.FirstName}}}`), related = `{{{Target__c.Name}}}` / `{{{Target__c.Billing_City__c}}}`. ALWAYS verify a template by actually rendering it (renderStoredEmailTemplate + System.debug the body) — a deploy success does NOT prove merge fields resolve.

**Why:** each cost a failed deploy / a reviewer rejection / a blocked feature; root causes were org/metadata behavior, not logic bugs.
**How to apply:** when adding Task/Event fields or CMDT rows in later features, follow these patterns up front, grant FLS before verifying field presence as a non-admin user, and cross-check CMDT-referenced picklist values against the field's restricted value set.
