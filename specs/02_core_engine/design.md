# Design — 02_core_engine

**Source:** Target_Sequence_Solution_Design.md §4, §4.1, §3.5, §8, §9

## Approach

Apex only. Build the layered core bottom-up: Selectors → `SequenceStepConfigService` →
`SequenceEmailService` → `SequenceEngineService`. The engine is a set of static methods
operating on collections, callable later by triggers/queueables (03), the batch (04), and
indirectly by the LWC's field write (06). The email service is the **single** place that
attaches the uploaded file — the reason the whole solution is Apex rather than Flow
(Solution Design §1, §4.1).

## Class layout (Trigger → Handler → Service → Selector)

```
classes/
  TargetSelector.cls        // inherited sharing; getByIds, getDueForScheduler (used by 04)
  TaskSelector.cls          // inherited sharing
  ContentSelector.cls       // inherited sharing; latest ContentVersion by ContentDocumentId
  SequenceStepConfigService.cls   // Map<Integer, Sequence_Step_Config__mdt> from getAll()
  SequenceEmailService.cls  // with sharing; send(List<EmailRequest>) + @InvocableMethod
  SequenceEngineService.cls // with sharing; processStep(...), bulk processSteps(...)
```

> Helper signatures (illustrative): `SequenceEngineService.processSteps(Map<Id,Target__c>
> targetsByStep)` where the value is the target and the desired `stepToSend`. Single-record
> callers wrap one entry. All public engine methods accept collections to stay bulk-safe.

## Engine flow — `processStep(Target__c t, Integer stepToSend)` (§4.1)

1. **Kill-switch guard** — `if (!t.Sequence_Active__c) { return; }` (R7).
2. Look up config `cfg = SequenceStepConfigService.get(stepToSend)`.
3. `SequenceEmailService.send(...)` — render `cfg.Email_Template_Dev_Name__c`, prefix
   `"RE: "` when `cfg.Is_Reply__c` (R4), attach `Sequence_Attachment_Id__c`'s latest
   `ContentVersion` when present (R5/R6), From = send-as-owner OWE matched to the Target
   owner's email, with fallback (R3/R14).
4. Build the `Call N` Task (R8b) and the completed Email Task (R8c).
5. Set `t.Sequence_Step__c = stepToSend` (R8d).
6. Schedule next per `cfg.Next_Trigger_Type__c`: `Timer` → `Next_Action_Date__c = now +
   Next_Wait_Days__c` (R9); `CallCompleted` → `null` (R10); `None` → leave null (R11).

The bulk method collects all emails, all tasks, and all target updates across the input
and performs **one** `Messaging.sendEmail`, **one** Task insert, and **one** Target update
(R12).

## Email construction (§3.5, §8)

- `setTemplateId` (resolved from `Email_Template_Dev_Name__c`), `setTargetObjectId(t.Primary_Contact__c)`,
  `setWhatId(t.Id)`, `setSaveAsActivity(false)` (we log our own completed Email task),
  `setOrgWideEmailAddressId(...)` set to the **send-as-owner** OWE (see below).
- Subject "RE: " prefix applied in Apex, not in the template (keeps one template per step).
- Attachment: `ContentSelector` fetches the latest `ContentVersion.Id` for
  `Sequence_Attachment_Id__c`; `setEntityAttachments(new List<String>{ contentVersionId })`.
- **No** `In-Reply-To`/`References` headers — true threading is out of scope (§8).

## Send-as-owner From resolution (R3, R14) — Option A

Salesforce only lets Apex send from a verified Org-Wide Email Address (OWE) or the running
user, so "send as the owner" is implemented as a runtime match of the owner's email to a
verified OWE. The work is fully bulkified (no SOQL in loops):

1. **Bulk-resolve owners' emails** — collect every `req.target.OwnerId` across all requests
   and run **one** `User` query over `Target.OwnerId`
   (`SELECT Id, Email FROM User WHERE Id IN :ownerIds WITH USER_MODE`), producing a
   `Map<Id ownerId, String email>` (and, by Target, the owner email per message).
2. **Bulk-resolve OWEs by address** — run **one** query
   `SELECT Id, Address FROM OrgWideEmailAddress WHERE Address IN :ownerEmails` and build a
   `Map<String oweAddressLower, Id> oweByAddress` (lower-cased keys for case-insensitive
   match).
3. **Per message** — `setOrgWideEmailAddressId(...)` to the owner's OWE id when
   `oweByAddress` contains the owner's (lower-cased) email; otherwise fall back to the
   default OWE (resolved by display name, as today) and ultimately to the running user
   (leave OWE id null).

**Testability constraint (seam):** `OrgWideEmailAddress` is **not insertable in Apex
tests**, so real OWEs cannot be created in a test. The owner-email → OWE matching must be
exposed via a `@TestVisible` seam — e.g. an injectable
`@TestVisible static Map<String oweAddressLower, Id>` (the resolved `oweByAddress` map) —
so unit tests can inject a known map and assert (a) an owner whose email is present selects
that OWE id, and (b) an owner whose email is absent falls back (null/default), all without
provisioning real OWEs.

**Option B POC removed:** the prior `Reply-To` = owner / sender-display-name approach
(shared OWE From + reply routing) is **removed** from `SequenceEmailService` and its tests,
along with `progress/poc_reply_to_owner.md`. Per the 2026-06-15 decision, the From is the
owner's OWE (send-as-owner), not a shared OWE with Reply-To.

## Security (§9, §14 dev rules)

- Services `with sharing`; selectors `inherited sharing`.
- All SOQL `WITH USER_MODE`; all DML `Database.*(..., AccessLevel.USER_MODE)` with
  `Database.SaveResult` checks (partial success).
- OWE + template Ids resolved at runtime (owner-email match / developer name / metadata) —
  never hardcoded.

## Bulkification (§9)

- Engine public methods take collections; internal loops only build in-memory lists.
- One `User` query for owner emails, one `OrgWideEmailAddress` query for OWE matching —
  both outside any loop.
- Exactly one `sendEmail`, one Task insert, one Target update per invocation.
- Config + selector results fetched once (CMDT via `getAll()` — no SOQL cost).

## Test approach (§12, conventions)

- `SequenceEngineServiceTest`, `SequenceEmailServiceTest`, selector + config tests.
- `@testSetup` builds Account + Contact + `Target__c` (active) and the CMDT is real
  metadata (deployed in 01).
- Email: use `Messaging.reserveSingleEmailCapacity` / test context so sends don't fail;
  assert no exception + that the Call task and completed Email task exist with correct
  fields, and `Sequence_Step__c`/`Next_Action_Date__c` are set per trigger type.
- **Send-as-owner (via the `@TestVisible` seam):** inject a known
  `Map<String oweAddressLower, Id>` and assert (a) a Target whose owner email is in the
  map selects that owner's OWE id, and (b) a Target whose owner email is absent falls back
  (no error, default/running-user path). No real `OrgWideEmailAddress` is created.
- **Bulk:** 200 active targets through the bulk method → assert step advancement on all,
  ≤1 DML per object (use `Limits`), no governor errors.
- **Guard:** inactive target → assert no tasks, no email, no field change (R7).
- Coverage target **>= 85%** for `SequenceEngineService`/`SequenceEmailService`.

## Open items / discrepancies

- **Apex email cap** (5,000/day) — design respects it; not a code branch. Monitor in prod
  (§10 item 2).
- **Stall behavior** for `CallCompleted` steps (no `Next_Action_Date__c` until the call is
  completed) is intentional here; the optional fallback timer, if adopted, would be a
  change to **03/04**, not this engine (§10 item 1).
