# Global Invoice Parser - Post-M2.5 Documentation and Test Pack

This is the implementation source of truth for a small, global-ready, human-supervised invoice-processing MVP built with Ruby on Rails and a provider-neutral extraction boundary.

**Project status supplied by the owner and implementation evidence:** M0, M1, and M2 are complete and frozen. The open-source model integration was introduced after M2 and is tracked as **M2.5**, not retroactively assigned to M2. M2.5 implementation fixtures now pass behind the unchanged provider contract, and M3 review workflow tests consume those outputs without controller-time model/provider calls. Permissioned real-corpus accuracy remains separate launch evidence when data is available.

This package contains documentation, schemas, prompts, planning assets, and a synthetic regression corpus alongside this Rails implementation.

## Frozen completed milestones

### M0 - scope and pilot contract

- Target workflow frozen.
- `global_generic_v1` selected as the first-live profile.
- Human-supervised, export-only MVP boundary accepted.

### M1 - deterministic invoice core

- Canonical Invoice Schema v2.
- Decimal and currency precision.
- Generic parties, identifiers, taxes, references, and line items.
- Arithmetic validation, duplicate fingerprints, and generic exports.

### M2 - intake, routing, and provider-neutral extraction foundation

- Safe intake and format routing.
- Visual, structured, hybrid, unsafe, and quarantine paths.
- Provider-neutral extraction contract.
- Processing provenance and idempotency contract.
- Bounded targeted-repair contract.
- Benchmark harness and initial structured-format detection.

M2 completion does **not** imply that Qwen3-VL, PaddleOCR-VL, or Docling were integrated during M2.

## M2.5 - open-source extraction upgrade

M2.5 adds local open-source implementations behind the completed M2 contract:

- **Docling/native parsing:** digital PDF text, tables, and page structure.
- **PaddleOCR-VL-1.6 full pipeline:** scanned-document OCR, layout, tables, reading order, and evidence boxes.
- **Qwen3-VL-4B-Instruct:** semantic mapping into Canonical Invoice v2.
- **Ruby deterministic services:** final authority for validation, acceptance, duplicates, and exports.
- **MLX-VLM:** optional Apple Silicon development runtime where supported.
- **Cloud fallback:** disabled by default and not required for M2.5 completion.

M2.5 must preserve the M2 provider contract and be removable through feature flags without changing Canonical Invoice v2 or the review domain.

## Remaining delivery sequence

- **M2.5 — Complete:** local route, benchmark harness, bounded repair, rollback, and M3 handoff evidence.
- **M3 — Complete:** operator review, corrections, immutable approval, M2.5-backed 50-document system keyboard flow, and approved-only exports.
- **M4 — Complete:** tenant authentication/isolation, private storage, retention/deletion, content-free logging, cost controls, deploy/restore checks, privacy approval gate, and upload-abuse CI coverage.
- **M5 — Planned:** closed supervised pilot and go/iterate/stop decision.

Read `docs/18_M2_FROZEN_AND_M2_5_HANDOFF.md` first.

## Synthetic test corpus

`samples/synthetic_corpus/` contains 29 fixtures covering currencies, tax patterns, document types, degraded images, structured payloads, duplicates, validation failures, and unsafe inputs.

These fixtures validate functional behavior and provide a reproducible M2.5 benchmark harness. They do not replace the permissioned real-document holdout required to approve model accuracy or a production capability claim.

## Recommended reading order

1. `docs/18_M2_FROZEN_AND_M2_5_HANDOFF.md`
2. `docs/23_M2_5_IMPLEMENTATION_PLAN.md`
3. `docs/19_OPEN_SOURCE_MODEL_STRATEGY.md`
4. `docs/22_MODEL_BENCHMARK_RUNBOOK.md`
5. `docs/21_MVP_REMAINING_WORK.md`
6. `docs/03_TECHNICAL_ARCHITECTURE.md`
7. `docs/04_EXTRACTION_VALIDATION_SPEC.md`
8. `docs/20_SYNTHETIC_CORPUS_GUIDE.md`
9. `docs/05_SECURITY_PRIVACY.md`
10. `docs/08_DELIVERY_PLAN.md`
11. `docs/15_FORMAT_SUPPORT_MATRIX.md`

## Key assets

- `contracts/invoice.schema.json` - Canonical Invoice v2.
- `reference/model_registry.yaml` - candidate model/parser/runtime roles.
- `prompts/qwen3_vl_*.txt` - local semantic extraction and targeted repair prompts.
- `planning/milestone_status.csv` - corrected milestone state.
- `planning/remaining_mvp_issues.csv` - M2.5 through M5 issue backlog.
- `samples/synthetic_corpus/manifest.csv` - test fixture index.
- `post_m2_5_mvp_tracker.xlsx` - milestone, issue, fixture, and benchmark tracker.
- `tools/generate_synthetic_corpus.py` - fixture regeneration tool.
