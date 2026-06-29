# M2 Frozen State and M2.5 Handoff

**Status source:** the project owner states that M0, M1, and M2 are complete. Those milestones are frozen. The open-source model strategy was selected afterward and is therefore implemented under M2.5.

## Why M2.5 exists

The completed M2 milestone established the extraction boundary and operational contracts. It must not be rewritten to claim implementation work that happened later.

M2.5 is a compatibility-preserving upgrade:

- it plugs local open-source parsers and vision-language models into the existing M2 provider interface;
- it does not alter Canonical Invoice v2 merely to accommodate a model;
- it does not move validation authority from deterministic Ruby services to a model;
- it does not require M3 controllers or views to know which model produced a candidate;
- it can be disabled or rolled back to the pre-M2.5 extraction provider through configuration.

## Frozen M2 contract

The system entering M2.5 is assumed to provide:

1. Secure upload and bounded file/page limits.
2. MIME and magic-byte inspection.
3. SHA-256 source identity.
4. Visual, structured, hybrid, unsupported, unsafe, and quarantine routes.
5. Embedded payload detection contract.
6. Provider-neutral extraction request/response contract.
7. Versioned processing provenance contract.
8. Idempotency keys and immutable candidate revision behavior.
9. One bounded targeted-repair contract.
10. Benchmark runner and per-field scoring interface.
11. Structured-format detection and safe quarantine behavior.

These capabilities are not reimplemented in M2.5 unless a compatibility defect is found.

## M2.5 objective

> Add and evaluate a local open-source extraction implementation behind the frozen M2 contract, select a reproducible configuration, and prove that failures are safely routed to review or quarantine.

## M2.5 candidate route

| Stage | Candidate implementation | Purpose |
|---|---|---|
| Digital PDF parsing | Docling or bounded native PDF parsing | Text, tables, reading order, and page structure |
| Scans and image evidence | PaddleOCR-VL-1.6 full pipeline | OCR, layout, tables, reading order, evidence boxes, quality signals |
| Canonical semantic mapping | Qwen3-VL-4B-Instruct | Map page/parsed content into Canonical Invoice v2 |
| Correctness | Deterministic Ruby services | Schema, arithmetic, required fields, duplicates, and acceptance |
| Fallback | Fixture provider/manual review initially | Deterministic development and safe failure handling |
| External API | Disabled by default | Optional later benchmark, not an M2.5 dependency |

The exact model revision, quantization, parser version, runtime, prompt hash, and device profile remain benchmark outputs until M2.5-08 freezes the selected configuration.

## Compatibility rules

M2.5 must:

- implement the existing extraction provider interface;
- return the existing candidate revision and finding contracts;
- record model/parser/runtime provenance in existing processing-attempt metadata;
- preserve idempotency behavior;
- keep raw model output out of application logs;
- create no direct model calls from Rails controllers;
- support a fixture provider so M3 UI work can proceed independently;
- be controlled by tenant/environment feature flags;
- fail closed to `needs_review`, `failed`, or `quarantined` states.

## M2.5 exit gate

M2.5 is complete only when:

- at least one local open-source route processes a supported visual invoice through the frozen M2 interface;
- output validates against Canonical Invoice v2 or is rejected safely;
- all enabled parser/model/runtime versions and prompt hashes are recorded;
- digital PDF and scan/image paths are exercised;
- invalid output follows a bounded repair or quarantine path;
- the 29-fixture synthetic corpus runs reproducibly;
- at least 25 ground-truth fixtures receive field-level benchmark results;
- latency, p95 latency, peak memory, crash/OOM rate, and repair rate are recorded;
- hallucinated non-null fields and evidence coverage are measured;
- a model-selection ADR documents the selected route and rejected alternatives;
- feature-flag disablement returns the application to the previous M2 provider behavior;
- M3 can consume the resulting candidates without contract changes.

Synthetic results are functional evidence. A permissioned real-document holdout remains required before M5 launch claims.

## Handoff into M3

M3 consumes only:

- immutable source metadata;
- candidate Canonical Invoice revisions;
- evidence references;
- validation findings;
- processing provenance;
- safe preview artifacts;
- route and capability profile.

M3 must not call Qwen, PaddleOCR, Docling, or any provider directly from controllers.

## Parallel-work rule

The following M3 work may begin during M2.5 using fixture-provider outputs:

- batch/document state UI;
- risk-ranked queue;
- document preview and canonical editor;
- corrections and immutable revisions;
- approved-only export integration.

The M3 end-to-end exit gate cannot pass until real M2.5 output has been connected and tested.
