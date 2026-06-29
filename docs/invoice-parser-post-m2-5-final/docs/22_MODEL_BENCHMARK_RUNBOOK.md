# M2.5 Model Benchmark Runbook

## Purpose

Select and approve a reproducible local open-source extraction configuration without rewriting M2 or confusing functional fixtures with production accuracy evidence.

## Benchmark layers

Run separate measurements for:

1. Digital PDF parsing through Docling/native parsing.
2. PaddleOCR-VL layout, OCR, table, and evidence recovery.
3. Qwen3-VL canonical semantic mapping.
4. End-to-end M2 provider route plus deterministic validation.
5. Bounded targeted repair.

Do not report only one aggregate score; it hides route-specific and field-specific failures.

## Reproducibility record

Record for every run:

- corpus version and checksum;
- model repository and exact revision;
- parser/OCR repository and exact revision;
- quantization and precision;
- inference runtime and version;
- device and memory profile;
- image resolution, page limits, and preprocessing;
- prompt and JSON Schema hashes;
- canonical schema/profile version;
- generation parameters;
- application commit;
- feature-flag/configuration ID;
- start and end timestamps.

## Field metrics

At minimum:

- supplier name normalized exact match;
- supplier identifier exact match;
- invoice number exact match;
- issue and due dates exact match;
- currency exact match;
- tax-exclusive, total-tax, and payable exact match;
- tax component/rate/amount precision, recall, and F1;
- line-item count exact match;
- quantity, unit price, and line-net exact match;
- description similarity;
- evidence page/text/bounding-box coverage;
- hallucinated non-null field rate;
- schema-valid output rate.

## Operational metrics

- median and p95 seconds per page/document;
- cold-start and warm latency;
- peak resident/unified/GPU memory;
- documents per hour at safe concurrency;
- crash, timeout, and OOM rates;
- repair and quarantine rates;
- model output size;
- queue delay;
- energy or GPU-minute estimate where measurable.

## Product metrics

Model selection must also estimate:

- percentage requiring operator review;
- unattended high-risk precision;
- escaped critical errors;
- correction minutes per document;
- end-to-end touch-time saving.

## Corpus policy

- Synthetic fixtures: functional regression and relative configuration comparison.
- Permissioned development set: prompt/routing iteration.
- Frozen real holdout: model selection and launch gate; never used for tuning.
- Failure set: development regression, separate from holdout.

## Required reports

M2.5 produces:

1. Synthetic functional report for all 29 fixtures.
2. Field-level scorecard for 25 ground-truth fixtures.
3. Route-specific latency/memory report.
4. Failure and quarantine report.
5. Permissioned real-corpus report when available.
6. Model-selection ADR with selected and rejected configurations.
7. Rollback verification report.

## M2.5 benchmark gate

The synthetic corpus alone cannot approve production accuracy. It can approve integration when:

- all supported routes execute reproducibly;
- unsafe inputs reject safely;
- schema-invalid/model-failure paths are bounded;
- provenance is complete;
- operational limits are known;
- M3 receives stable candidate/finding contracts.
