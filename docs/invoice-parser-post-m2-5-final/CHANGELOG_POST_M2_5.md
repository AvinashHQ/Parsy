# Post-M2.5 Package Changelog

## 2026-06-29 — milestone correction

- Preserved M0, M1, and M2 as completed and frozen.
- Added M2.5 as the post-M2 open-source extraction upgrade.
- Removed claims that Qwen3-VL, PaddleOCR-VL, or Docling were already integrated in M2.
- Added eight M2.5 implementation issues, exit gate, observability requirements, and rollback policy.
- Updated the critical path to `M2 -> M2.5 -> M3 -> M4 -> M5`.
- Clarified that fixture-driven M3 UI work may proceed in parallel, while M3 end-to-end completion requires M2.5 output.
- Updated architecture, ADRs, delivery plan, support matrix, benchmark runbook, planning CSVs, tracker, HTML handoff, and manifests.

## Existing post-M2 assets retained

- 29 synthetic functional and negative fixtures.
- 25 Canonical Invoice v2 ground-truth records.
- PDF, image, TIFF, XML, hybrid, duplicate, validation, and unsafe-input samples.
- Qwen, PaddleOCR-VL, Docling candidate prompts/registry entries.
- Deterministic expected findings and export examples.
