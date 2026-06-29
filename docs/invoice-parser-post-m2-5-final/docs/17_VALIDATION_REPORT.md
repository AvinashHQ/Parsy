# Documentation and Contract Validation Report

**Review date:** 29 June 2026  
**Package:** Global Invoice Parser — Post-M2.5 Documentation and Sample Pack

## Review conclusion

The package now preserves the declared project history:

- M0, M1, and M2 are complete and frozen.
- The open-source extraction decision is explicitly assigned to M2.5.
- M2 no longer claims Qwen3-VL, PaddleOCR-VL, or Docling integration.
- M3 remains the review milestone and may begin against fixture/provider-contract outputs while M2.5 runs.

The product is global-ready, not globally certified. Regional tax semantics, languages, structured syntaxes, and ERP adapters remain separately benchmarked capabilities.

## Automated and structural checks expected

- JSON, YAML, CSV, and HTML assets parse successfully.
- Canonical samples validate against Canonical Invoice Schema v2.
- The synthetic corpus manifest and checksums are consistent.
- Planning files contain M2.5 and no contradictory M2 model-integration claims.
- The workbook contains M2.5 status, issues, fixtures, and benchmark columns.
- The documentation archive contains no generated Rails application boilerplate.

## Cross-document consistency

- `docs/08_DELIVERY_PLAN.md`, planning CSV files, README, HTML handoff, and tracker use the critical path `M2 -> M2.5 -> M3`.
- M2.5 has eight issues with acceptance criteria, dependencies, observability, and rollback expectations.
- M3 UI work may use fixture outputs in parallel, but its real end-to-end gate requires M2.5.
- Synthetic fixtures are functional evidence, not launch accuracy evidence.
- Deterministic Ruby validation remains the final authority.

## Known limitations requiring implementation evidence

1. M0-M2 completion is owner-declared and must be supported by application-repository evidence.
2. Open-source model accuracy has not been approved on a permissioned frozen holdout.
3. Hardware-specific latency and memory must be measured.
4. Model/parser licenses and exact revisions must be recorded for the selected configuration.
5. Non-English and regional support claims remain independently gated.
6. M4 security, deletion, restore, and deployment evidence remains outstanding.

## Next implementation action

Start M2.5 contract snapshot and provider feature flags. M3 can concurrently build its first review slice using deterministic fixture candidates.
