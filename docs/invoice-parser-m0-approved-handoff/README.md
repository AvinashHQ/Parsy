# Global Invoice Parser — M0 Approved Handoff

**Decision:** `GO TO M1`  
**Decision date:** 2026-06-29  
**Evidence status:** synthetic planning scenario; read `ASSUMPTION_NOTICE.md` first.

This package represents the complete output expected when Milestone M0 has produced positive findings and the project is ready to begin actual product development in Milestone M1.

## What M0 decided

- The first commercial workflow is **batch visual invoices → reviewed normalized XLSX/CSV**.
- The operator remains responsible for approval; there is no direct accounting-system posting.
- The core is country-neutral. Regional tax semantics remain versioned capability packs.
- English, Latin-script documents across multiple countries and currencies form the first live cohort.
- Header fields and totals are mandatory. Line items are conditional per pilot profile and never auto-accepted initially.
- Unsupported structured files are detected and quarantined rather than guessed.
- The project may start M1 because the customer, workflow, fields, error policy, corpus plan, capability statement, and privacy boundary are frozen.

## Start here

1. `M0_EXIT_REPORT.md` — formal closeout and gate evidence.
2. `M0_DECISION_RECORD.md` — product decisions that are now binding.
3. `m1/M1_HANDOFF.md` — exact implementation order.
4. `m1/M1_DEFINITION_OF_READY.md` — conditions already satisfied.
5. `pilot/PILOT_PROFILE_V1.md` — first-live workflow contract.
6. `pilot/REQUIRED_FIELDS_V1.yaml` and `pilot/BLOCKING_ERRORS_V1.yaml` — implementation inputs.

## Folder map

- `research/` — assumed interview synthesis and baseline evidence.
- `pilot/` — frozen capability, field, corpus, privacy, and pilot decisions.
- `planning/` — milestone status and issue-level handoff.
- `m1/` — M1 development sequence, fixtures, and definition of done.
- `project-docs/` — M0-approved updates for the project documentation.
- `contracts/`, `reference/`, `evaluation/`, `samples/` — carried-forward technical inputs from the global documentation package.

## Important scope note

M1 begins actual implementation, but the **live working MVP spans M1–M4**:

- M1: canonical contract and deterministic core
- M2: intake, routing, extraction and benchmark runner
- M3: human review and safe acceptance
- M4: security, reliability and deployability

M5 is the closed live test.
