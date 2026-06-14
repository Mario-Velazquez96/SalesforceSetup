---
name: bluesky-org-coverage-and-owe
description: BlueSky sandbox quirks that affect every cadence feature deploy — org-wide coverage and missing Org-Wide Email Address
metadata:
  type: project
---

Two BlueSky sandbox conditions confirmed during feature 02_core_engine that recur on every Apex feature (03/04/05/06):

1. **Org-wide Apex coverage reads ~52%, NOT because of our code.** The org contains pre-existing, out-of-scope Salesforce sample classes sitting at 0% that drag the org-wide number down. Judge coverage per-feature-class (our classes run 96–100%), not by the org-wide figure. AGENTS.md's 85% rule was accepted as satisfied by the reviewer for 02 on this basis. Expect to make the same argument for later features. (If a deploy is ever attempted to production, that 85% org-wide gate WOULD block — sandbox validate only.)

2. **The BlueSky org has NO OrgWideEmailAddress.** `SELECT ... FROM OrgWideEmailAddress` returns 0 rows. SequenceEmailService resolves the OWE by DisplayName and degrades gracefully (sends as the running user) when none is found — this is intended per R3/R14 and is NOT a hardcoded fallback. Email-related tests/features should not assume an OWE exists.

**Why:** both surfaced as reviewer caveats on 02 and would otherwise look like failures.
**How to apply:** when reviewing/closing 03–06, report feature-class coverage explicitly and treat the org-wide 52% as the known sample-class artifact; don't add a fake OWE to make email code "work." See [[salesforce-org-gotchas]].

CLI note for this environment: invoke the Salesforce CLI as `cmd //c "sf ... --target-org BlueSky --json"` (the bash wrapper mishandles the space in "C:\Program Files"); pass comma-containing SOQL via `--file`.
