# Milestone M1 Handoff

## Objective

Create a country-neutral system of record and deterministic accounting checks before integrating a vision model or building operator UI behavior.

## Entry decision

**READY.** M0 has frozen the target workflow, field profile, blocking errors, currency/global requirements, export boundary, corpus plan and privacy constraints.

## Implementation order

### Slice 1 — Contract foundation

1. **M1-01:** implement `canonical_invoice_v2` value objects and JSON Schema validation.
2. **M1-07:** implement schema/profile version compatibility and migration policy.
3. Create the fixture harness listed in `fixture_manifest.csv`.

Reason: versioning must exist before persistent data or exports depend on the contract.

### Slice 2 — Decimal and global primitives

4. **M1-02:** decimal-string parser, normalization and ISO currency minor-unit registry.
5. Prove USD/EUR/GBP two-decimal, JPY zero-decimal and KWD three-decimal behavior.

### Slice 3 — Canonical domain breadth

6. **M1-03:** parties, generic identifiers, addresses, references, classifications, tax breakdowns, allowances/charges and line items.
7. Enforce the rule that country-specific concepts do not create core columns.

### Slice 4 — Deterministic safety

8. **M1-04:** universal arithmetic, completeness, severity and evidence findings.
9. Implement blocking policies from `pilot/BLOCKING_ERRORS_V1.yaml` as test inputs, not hard-coded UI behavior.
10. **M1-05:** normalized search keys and duplicate fingerprint.

### Slice 5 — Stable output

11. **M1-06:** canonical JSON, CSV bundle and XLSX export model.
12. Reconcile every export against the canonical object.
13. Defend CSV/XLSX output against formula injection.

## Required architecture

- Rails modular monolith
- PostgreSQL
- immutable schema/profile version fields on canonical revisions
- decimal arithmetic; never binary floating-point money
- domain services independent of controllers/jobs
- tests runnable without AI provider or object storage
- no regional tax pack enabled in M1

## M1 non-goals

- OCR/vision provider calls
- upload UI
- Active Storage pipeline
- review screens
- queue orchestration
- acceptance/auto-accept engine
- direct ERP integrations
- regional compliance validation

## M1 demonstration

At completion, a developer can load a fixture, validate and normalize it, run deterministic findings, compute a duplicate key, and export reconciled JSON/CSV/XLSX without any external API.

## Exit gate

- all M1 issues complete;
- fixtures pass;
- no country-specific core columns;
- JPY/USD/KWD precision passes;
- universal arithmetic fixtures pass;
- duplicate fixtures pass;
- export reconciliation and formula-injection tests pass;
- version migration fixtures pass.
