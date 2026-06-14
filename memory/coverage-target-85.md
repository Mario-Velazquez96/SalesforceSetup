---
name: coverage-target-85
description: Apex coverage target for cadence features is 85%, not 95% — user-confirmed standard
metadata:
  type: feedback
---

The Apex test coverage target for features in this repo is **≥ 85%** (per-feature class), not 95%. The user explicitly confirmed 85% is acceptable for all future features (2026-06-13).

**Why:** the project design doc `project-documents/solution_design.md` (line ~343) says "Apex 95%+ target", and feature 02_core_engine used 95% — but the user wants 85% going forward to match `docs/conventions.md` / `docs/verification.md` and AGENTS.md.

**How to apply:** when spec_author authors or revises any feature spec, set the coverage target to ≥ 85% (do not copy the 95% from solution_design.md). When the reviewer/implementer judge "done", 85% per feature class is the gate. Features 03/04/05/06 specs already say ≥85% — leave them. Do not retroactively change the done 02_core_engine records (it was genuinely 96%). See [[bluesky-org-coverage-and-owe]] for why org-wide coverage reads ~52% regardless.
