# MVP Milestones and Issue Map

## Current status — 29 June 2026

| Milestone | Status | Note |
|---|---|---|
| M0 | Complete | Scope and pilot contract frozen |
| M1 | Complete | Canonical and deterministic core complete |
| M2 | Complete and frozen | Intake, routing, provider contract, provenance, repair contract, and benchmark harness complete |
| M2.5 | Complete | Local route, provenance, benchmark harness, bounded repair, rollback, and M3 handoff tests pass |
| M3 | Complete | Persisted review workflow, 50-document fixture exit gate, safe acceptance, audit, and approved-only exports pass |
| M4 | Planned | Launch security and operations |
| M5 | Planned | Closed live pilot |
| M6 | Deferred | One evidence-backed expansion after M5 |

M0-M2 status is supplied by the project owner. New open-source integration work is not backdated into M2. See `docs/18_M2_FROZEN_AND_M2_5_HANDOFF.md`.

## Milestone M0 — Pilot contract and scope freeze

Completed and frozen. See the M0 handoff and business-validation documents.

## Milestone M1 — Canonical contract and deterministic core

Completed and frozen. Canonical Invoice v2, currency/decimal handling, generic tax/party structures, deterministic validation, duplicate fingerprinting, exports, and schema versioning are the compatibility boundary.

## Milestone M2 — Intake, routing, and provider-neutral extraction foundation

Completed and frozen.

| Issue | Work | Primary output |
|---|---|---|
| M2-01 | Secure upload, file limits, MIME/magic-byte validation, SHA-256 | Intake tests |
| M2-02 | Format detector and quarantine route | Format registry/tests |
| M2-03 | PDF metadata/attachment and hybrid-payload detection | Detector fixtures |
| M2-04 | Provider-neutral extraction adapter with strict schema output | Provider contract tests |
| M2-05 | Processing provenance and idempotency | Processing-attempt tests |
| M2-06 | One bounded targeted-repair contract | Repair contract tests |
| M2-07 | Benchmark runner and per-field scoring | Evaluation harness |
| M2-08 | Initial structured-format detection and safe quarantine | Structured fixtures |

M2 does not claim Qwen3-VL, PaddleOCR-VL, or Docling integration.

## Milestone M2.5 — Open-source extraction upgrade

**Goal:** add and select local open-source implementations behind the frozen M2 provider contract.

| Issue | Work | Primary output | Dependency |
|---|---|---|---|
| M2.5-01 | Snapshot M2 provider contract; add fixture/local provider flags and rollback | Contract/feature-flag tests | M2 |
| M2.5-02 | Integrate Docling or bounded native PDF parser | Digital-PDF parser report | M2.5-01 |
| M2.5-03 | Integrate PaddleOCR-VL complete scan/layout/OCR pipeline | OCR/layout/evidence report | M2.5-01 |
| M2.5-04 | Integrate Qwen3-VL canonical semantic extractor | Provider/schema tests | M2.5-01 |
| M2.5-05 | Compose routes and preserve provenance/idempotency | End-to-end route tests | M2.5-02/03/04 |
| M2.5-06 | Benchmark synthetic and permissioned real corpora | Benchmark reports | M2.5-05 |
| M2.5-07 | Connect bounded repair and safe failure/quarantine | Failure/repair tests | M2.5-04/05 |
| M2.5-08 | Select configuration; approve ADR, rollout, and rollback | ADR and rollback evidence | M2.5-06/07 |

**Exit gate:** one selected local route processes supported documents through the unchanged M2 interface, records complete provenance and operational metrics, passes functional fixtures, and can be disabled without a schema/domain change.

## Milestone M3 — Review workflow and acceptance engine

**Goal:** let an operator complete a batch faster while preventing unsafe acceptance.

| Issue | Work | Primary output | Dependency |
|---|---|---|---|
| M3-01 | Implement batch/document states and Solid Queue orchestration | State-transition tests | M2; fixture provider |
| M3-02 | Build batch progress and risk-ranked review queue | Hotwire screens | M3-01 |
| M3-03 | Build source/evidence viewer and canonical editor | System tests | M3-02 |
| M3-04 | Show/override language, country, currency, format, and rule pack | Review UI | M3-03 |
| M3-05 | Implement deterministic acceptance policy | Acceptance service tests | M1-04; M2.5-06 |
| M3-06 | Add audit metadata and approved revision immutability | Audit tests | M3-03 |
| M3-07 | Add keyboard-first review actions | Timing/system tests | M3-03 |
| M3-08 | Generate exports only from approved revisions | Export integration tests | M1-06; M3-06 |

Fixture-driven M3 UI work may run in parallel with M2.5. The M3 exit gate requires real M2.5 output.

**Exit gate:** an operator completes a 50-document batch; no unresolved critical/high finding auto-accepts; every changed high-risk field has evidence or explicit confirmation; approved revisions are immutable.

## Milestone M4 — Security, privacy, reliability, and deployment

| Issue | Work | Dependency |
|---|---|---|
| M4-01 | Authentication and tenant isolation | M3 |
| M4-02 | Private object storage and short-lived access | M2-01 |
| M4-03 | Purge, retention, and deletion verifier | M4-02 |
| M4-04 | Content-free logging proof | M2.5; M3 |
| M4-05 | Quotas, model/runtime limits, and circuit breaker | M2.5-05 |
| M4-06 | Deploy web/job/database roles and backups | M4-01/02 |
| M4-07 | Restore and recovery drills | M4-06 |
| M4-08 | Privacy, subprocessors, residency, and launch approval | M0-07; M4-03/04 |
| M4-09 | Security CI and upload-abuse suite | M4-01 |

**Exit gate:** tenant isolation, deletion, restore, content-free logging, resource controls, and privacy approval pass.

## Milestone M5 — Closed live MVP test

| Issue | Work | Dependency |
|---|---|---|
| M5-01 | First supervised 50-document batch | M4 |
| M5-02 | Correction taxonomy and root causes | M5-01 |
| M5-03 | Two-week 500-document pilot | M5-01 |
| M5-04 | Measure safety, speed, accuracy, and cost | M5-03 |
| M5-05 | Re-run frozen holdout after every relevant change | M5-02 |
| M5-06 | Operator debrief and willingness to pay | M5-03 |
| M5-07 | Go, iterate, or stop decision | M5-04/06 |

**Go gate:** material time savings, at least 99.5% precision for any unattended high-risk cohort, zero escaped critical monetary errors, acceptable unit economics, and at least one pilot request to continue.

## Milestone M6 — First demanded regional or structured capability

Deferred until M5 evidence selects exactly one region pack, structured adapter, or ERP export.

## Critical path

`M0 -> M1 -> M2 -> M2.5 -> M3 -> M4 -> M5`

M2.5 fixture/provider-contract evidence now satisfies the M3 implementation handoff; permissioned real-corpus accuracy remains separate launch evidence when available.

## Issue discipline

Every implementation issue must contain:

- acceptance criteria;
- test/fixture reference;
- affected schema/profile version;
- privacy/logging impact;
- observability signal;
- rollback or feature-flag plan when external behavior changes.
