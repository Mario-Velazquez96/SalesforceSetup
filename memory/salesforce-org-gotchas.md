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

**Why:** each cost a failed deploy / a reviewer rejection; root causes were org/metadata behavior, not logic bugs.
**How to apply:** when adding Task/Event fields or CMDT rows in later features, follow these patterns up front and grant FLS before verifying field presence as a non-admin user.
