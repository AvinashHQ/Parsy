# MVP Milestones and Issue Map

This is the execution plan for the first working MVP that can be deployed for an invite-only initial test. Issue IDs are stable and mirrored in `planning/mvp_issues.csv`.

## Milestone M0 — Pilot contract and scope freeze

**Goal:** establish exactly what the first live test must process and what it will not claim.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M0-01 | Interview at least five operators and capture current workflow/time/errors | `docs/09_BUSINESS_VALIDATION.md` notes | None |
| M0-02 | Select two pilot teams and one operating language | Signed pilot/DPA checklist | M0-01 |
| M0-03 | Inventory countries, currencies, languages, file types, document types, and export needs | Capability baseline CSV | M0-02 |
| M0-04 | Agree critical fields, unacceptable errors, and review responsibility | PRD pilot profile | M0-02 |
| M0-05 | Freeze first-live capability statement and unsupported scenarios | `docs/15_FORMAT_SUPPORT_MATRIX.md` | M0-03/04 |
| M0-06 | Collect 150–300 permissioned documents and double-label the first 100 | Golden dataset manifest | M0-02 |
| M0-07 | Confirm retention, subprocessors, hosting region, and transfer requirements | Security launch checklist | M0-02 |

**Exit gate:** two pilot teams agree that generic JSON/CSV/XLSX output is useful, provide permissioned ground truth, and accept supervised export-only testing.

## Milestone M1 — Canonical contract and deterministic core

**Goal:** create a country-neutral system of record before building model or UI behavior.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M1-01 | Implement Canonical Invoice Schema v2 value objects | `contracts/invoice.schema.json` | M0-04 |
| M1-02 | Implement decimal-string parser and ISO currency minor-unit registry | Validation unit tests | M1-01 |
| M1-03 | Implement party identifiers, tax breakdowns, classifications, references, addresses | Schema fixtures | M1-01 |
| M1-04 | Implement universal arithmetic validators and severity model | `reference/validation_rules.yaml` | M1-02/03 |
| M1-05 | Implement duplicate fingerprint and normalized search keys | Architecture/database spec | M1-03 |
| M1-06 | Build canonical JSON/CSV/XLSX exporters | Sample export fixtures | M1-01 |
| M1-07 | Add schema migration/versioning policy | ADR and migration tests | M1-01 |

**Exit gate:** all sample invoices in at least USD, EUR, INR, and JPY/KWD precision cases validate and export without country-specific columns.

## Milestone M2 — Intake, routing, and extraction harness

**Goal:** reliably turn files into versioned canonical candidates.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M2-01 | Build secure upload, file limits, MIME/magic-byte validation, SHA-256 | Intake request tests | M1 |
| M2-02 | Build format detector and quarantine route | `reference/format_registry.yaml` | M2-01 |
| M2-03 | Extract PDF metadata/attachments and detect hybrid structured payloads | Detector fixtures | M2-02 |
| M2-04 | Implement managed-model provider adapter with strict schema output | Provider contract tests | M1-01 |
| M2-05 | Implement extraction pipeline provenance and idempotency | ProcessingAttempt model spec | M2-04 |
| M2-06 | Add one targeted repair path; prohibit broad retry loops | Repair tests | M2-04 |
| M2-07 | Implement benchmark runner and per-field scoring | Evaluation report | M0-06, M2-04 |
| M2-08 | Add initial UBL/CII detection adapter; deterministic parsing may remain feature-flagged | Structured fixtures | M2-02 |

**Exit gate:** one command processes the frozen holdout, records exact versions/cost/route, and produces reproducible metrics; unsupported structured files are quarantined safely.

## Milestone M3 — Review workflow and acceptance engine

**Goal:** let an operator complete a batch faster while preventing unsafe auto-acceptance.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M3-01 | Implement batch/document states and Solid Queue orchestration | State-transition tests | M2 |
| M3-02 | Build batch progress and risk-ranked review queue | Hotwire screens | M3-01 |
| M3-03 | Build source/evidence viewer and canonical editor | System tests | M3-02 |
| M3-04 | Show/override language, country, currency, format, and rule pack | Review UI | M3-03 |
| M3-05 | Implement acceptance policy from deterministic findings and benchmark profile | Acceptance service tests | M1-04, M2-07 |
| M3-06 | Add audit metadata and approved revision immutability | Audit tests | M3-03 |
| M3-07 | Add keyboard-first save/approve/reject/next actions | System test timing | M3-03 |
| M3-08 | Generate generic export only from approved revisions | Export integration tests | M1-06, M3-06 |

**Exit gate:** an operator completes a 50-document batch end-to-end; no critical/high finding auto-accepts; every edited value has evidence or explicit operator confirmation.

## Milestone M4 — Security, privacy, reliability, and deployment

**Goal:** make the supervised MVP safe enough to expose to initial testers.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M4-01 | Implement authentication, tenant scoping, and secure cookies/headers | Security tests | M3 |
| M4-02 | Implement private object storage and short-lived access | Storage tests | M2-01 |
| M4-03 | Implement purge-now, retention jobs, and orphan reconciliation | Deletion verifier | M4-02 |
| M4-04 | Prove content-free logs, exception payloads, and job arguments | Logging test report | M2/M3 |
| M4-05 | Implement quotas, spend ceilings, retry limits, and circuit breaker | Operations tests | M2-04 |
| M4-06 | Deploy web/job roles and database backups | Deployment runbook | M4-01/02 |
| M4-07 | Perform restore drill and failed-job recovery drill | Drill evidence | M4-06 |
| M4-08 | Complete pilot privacy/subprocessor/residency launch checklist | Signed approval | M0-07, M4-03/04 |
| M4-09 | Run dependency, static security, and upload abuse checks | CI evidence | M4-01 |

**Exit gate:** restore and deletion tests pass, content is absent from logs, tenant isolation tests pass, spend controls are active, and the pilot privacy checklist is approved.

## Milestone M5 — Closed live MVP test

**Goal:** validate time savings, accuracy, cost, and willingness to continue.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M5-01 | Process first 50-document supervised batch | Pilot scorecard | M4 |
| M5-02 | Classify every correction by field, format, language, and root cause | Correction taxonomy | M5-01 |
| M5-03 | Process at least 500 documents over two weeks | Pilot report | M5-01 |
| M5-04 | Measure review time, extraction cost, auto-accept precision, and escaped errors | Workbook dashboard | M5-03 |
| M5-05 | Re-run frozen holdout after every prompt/rule change | Regression reports | M5-02 |
| M5-06 | Conduct operator debrief and willingness-to-pay interview | Business validation | M5-03 |
| M5-07 | Decide go, iterate, or stop | Decision record | M5-04/06 |

**Go gate:** both pilot teams achieve ≥50% time savings or one achieves materially higher savings with clear repeatability; auto-accepted high-risk precision ≥99.5%; zero escaped critical monetary errors; unit economics are acceptable; at least one team requests continued use.

## Milestone M6 — First demanded regional/structured capability after MVP

**Goal:** add exactly one evidence-backed capability without weakening the global core.

| Issue | Work | Primary document/output | Dependency |
|---|---|---|---|
| M6-01 | Use pilot evidence to choose one regional pack, structured adapter, or ERP export | `planning/region_backlog.csv` decision | M5-07 |
| M6-02 | Pin official schemas, code lists, validators, and permitted fixtures | Research/version manifest | M6-01 |
| M6-03 | Implement the versioned adapter or region pack behind a feature flag | Profile/adapter contract tests | M6-02 |
| M6-04 | Build an independent holdout and conformance regression suite | Profile benchmark report | M6-03 |
| M6-05 | Publish the named capability statement, rollout plan, and rollback path | Support matrix and runbook | M6-04 |

Candidate capabilities include India GST plus a tested Tally adapter, Peppol/EN 16931 read-only ingestion, a UK/EU VAT profile, a US/Canada sales-tax profile, or another capability proven by pilot demand. Do not parallelize them.

**Exit gate:** the named profile passes its independent extraction, semantic, export, or conformance gate; the capability matrix is updated; and disabling the feature does not affect `global_generic_v1`.

## Critical path

`M0 → M1 → M2 → M3 → M4 → M5`

M6 is not required to make the generic MVP live.

## Issue discipline

Every implementation issue must contain:

- acceptance criteria;
- test/fixture reference;
- affected schema/profile version;
- privacy/logging impact;
- observability signal;
- rollback or feature-flag plan when external behavior changes.
