# M2.5 Open-Source Extraction Upgrade — Implementation Plan

## Milestone statement

**Status:** Complete for implementation fixtures and M3 handoff; permissioned real-corpus accuracy evidence remains separate launch evidence when available.

**Dependency:** completed and frozen M2 provider-neutral extraction foundation.

**Goal:** integrate and benchmark an open-source local extraction route without retroactively changing M2 or coupling the Rails domain to a specific model runtime.

## Issues

### M2.5-01 — Freeze compatibility contract and feature flags

**Work**

- Capture the current M2 extraction request, response, error, provenance, and idempotency contracts as executable contract tests.
- Add `fixture`, `local_open_source`, and existing-provider selection through configuration.
- Define tenant/environment rollout and immediate rollback behavior.

**Acceptance**

- Existing M2 contract tests pass unchanged.
- Switching providers does not alter Canonical Invoice v2 or review-domain APIs.
- Disablement restores the previous provider without data migration.

### M2.5-02 — Digital PDF parser adapter

**Work**

- Add Docling or a bounded native PDF parser behind a parser interface.
- Extract page text, table structure, reading order, and page references.
- Record exact parser version and options.

**Acceptance**

- Clean digital-PDF fixtures produce stable page-level structured content.
- Parser failure is classified and never exposes document content in logs.

### M2.5-03 — Scan/layout/OCR adapter

**Work**

- Integrate the complete PaddleOCR-VL pipeline, not only the recognition model.
- Produce OCR text, reading order, tables, bounding boxes, and quality warnings.
- Normalize rotation and bounded page images before inference.

**Acceptance**

- Blurred, rotated, skewed, image, and TIFF fixtures return evidence or a safe quality failure.
- Exact model/runtime revision and peak memory are recorded.

### M2.5-04 — Canonical semantic extraction adapter

**Work**

- Integrate Qwen3-VL-4B-Instruct through the existing provider contract.
- Generate Canonical Invoice v2 candidate JSON.
- Use deterministic settings and versioned prompts.
- Preserve nulls/ambiguity instead of inventing values.

**Acceptance**

- Supported fixtures produce schema-valid candidates or explicit schema errors.
- No candidate is accepted based on model confidence.
- Model revision, quantization, runtime, prompt hash, latency, and device are persisted.

### M2.5-05 — Route orchestration and provenance

**Work**

- Select digital-PDF, scan/image, structured, hybrid, or quarantine route using completed M2 detection.
- Compose parser/OCR output with semantic extraction.
- Reuse M2 idempotency and attempt records.

**Acceptance**

- Reprocessing an identical document/configuration does not duplicate candidate state.
- Route decisions and every implementation version are reproducible.

### M2.5-06 — Benchmark and compare configurations

**Work**

- Run all 29 synthetic fixtures.
- Score at least 25 ground-truth fixtures.
- Run a separate permissioned real-document development set and frozen holdout when available.
- Compare model sizes, quantizations, parser routes, latency, memory, and accuracy.

**Acceptance**

- Field-level, evidence, hallucination, latency, memory, and failure metrics are published.
- Synthetic and real-corpus metrics are never merged into one accuracy claim.

### M2.5-07 — Bounded repair and safe failure handling

**Work**

- Connect the completed M2 targeted-repair contract to the local provider.
- Allow one field-scoped repair attempt.
- Route unresolved schema or semantic failures to review/quarantine.

**Acceptance**

- Unrelated fields cannot change during targeted repair.
- Retry loops are bounded.
- OOM, timeout, corrupt document, and invalid JSON cases fail safely.

### M2.5-08 — Select configuration and approve ADR

**Work**

- Select the initial parser/model/runtime/quantization/device profile.
- Record support boundaries and disabled routes.
- Approve rollout, monitoring, and rollback rules.

**Acceptance**

- ADR identifies selected and rejected configurations with evidence.
- The selected route can feed M3 without a domain-contract change.
- Feature-flag rollback is tested.

## Test fixtures

Use `samples/synthetic_corpus/manifest.csv` as the functional suite. The initial route smoke set is:

- `INV-002` — clean digital PDF.
- `INV-011` — multipage line items.
- `IMG-001` — blurred low-resolution scan.
- `IMG-002` — rotated image.
- `IMG-003` — phone-photo skew.
- `IMG-005` — multipage TIFF.
- `INV-014` — arithmetic mismatch retained for deterministic validation.
- `INV-016` — ambiguous invoice number.
- `HYB-001` — hybrid PDF.
- `XML-002` — unknown structured profile quarantine.
- `BAD-001`, `BAD-002`, `BAD-003` — safe failure inputs.

## Observability

Record content-free metrics:

- route and model/parser configuration ID;
- pages and image resolution class;
- latency and queue delay;
- peak memory and OOM count;
- schema-valid rate;
- repair and quarantine rates;
- evidence coverage;
- field-level exact-match metrics in benchmark jobs;
- hallucinated non-null fields;
- provider disable/rollback events.

Do not record source text, evidence snippets, party names, invoice numbers, account numbers, or model response bodies in logs.

## Definition of done

- [x] M2 contract snapshot tests pass.
- [x] Feature flags and rollback path work.
- [x] Digital PDF adapter works.
- [x] Scan/layout/OCR adapter works.
- [x] Semantic extraction adapter works.
- [x] Provenance and idempotency remain intact.
- [x] Synthetic benchmark report is complete.
- [ ] Permissioned real-corpus benchmark is recorded when permissioned data is available; current completion evidence is synthetic/fixture-based only.
- [x] Bounded repair and failure tests pass.
- [x] Model-selection ADR is approved.
- [x] M3 consumes the output with no contract change.
