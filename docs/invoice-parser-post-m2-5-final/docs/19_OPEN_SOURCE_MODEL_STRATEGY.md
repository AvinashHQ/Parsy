# Open-Source Model Strategy — M2.5

## Decision

Implement the open-source-first extraction route as a **post-M2 compatibility upgrade**. M2 remains complete and frozen. M2.5 plugs model and parser implementations into the provider-neutral M2 contract.

The deterministic Rails core remains the authority for correctness and acceptance.

## Candidate components

### Qwen3-VL-4B-Instruct — semantic extractor

Model identifier: `Qwen/Qwen3-VL-4B-Instruct`

Responsibilities:

- identify invoice concepts from document pages or parsed page content;
- map header fields, parties, references, taxes, totals, and line items;
- produce Canonical Invoice v2 candidate JSON;
- return null/ambiguity rather than inventing unsupported values;
- support one targeted repair of named field paths.

Constraints:

- deterministic generation settings;
- schema-constrained output where supported;
- exact revision, quantization, runtime, prompt hash, and device recorded;
- no chain-of-thought storage;
- no model-confidence-based acceptance;
- bounded pages, pixels, latency, and memory.

### PaddleOCR-VL-1.6 — layout, OCR, and evidence

Use the complete document pipeline rather than only the recognition component.

Responsibilities:

- OCR for scans and images;
- layout and reading order;
- table and line-item structure;
- page/source text and bounding boxes;
- quality diagnostics used to force review.

### Docling or bounded native PDF parsing — digital PDF route

Responsibilities:

- native text extraction;
- page and reading-order structure;
- table recovery where reliable;
- evidence references;
- structured input to the semantic extractor.

## Provider boundary

Rails communicates with a separately deployed local inference service through the existing M2 adapter contract.

```text
Rails web/job
    |
    +-- fixture/existing provider
    |
    +-- local_open_source provider
          |
          +-- digital PDF -> Docling/native parser -> semantic mapping
          +-- scan/image  -> PaddleOCR-VL -> semantic mapping
          +-- structured  -> completed M2 deterministic route
```

Rails must not import Python, model weights, CUDA, MLX, or OCR runtime dependencies into the web process.

## M2.5 rollout policy

1. Start with fixture provider in M3 development.
2. Enable local open-source route in development only.
3. Benchmark the complete synthetic corpus.
4. Benchmark permissioned real documents separately.
5. Enable for an internal shadow run.
6. Enable for selected pilot tenants with forced review.
7. Permit any unattended cohort only after product acceptance gates pass.

## Rollback

- Feature flag disables `local_open_source` provider.
- Existing candidate revisions remain immutable and reviewable.
- New jobs return to the previous M2 provider or fixture/manual-review path.
- No canonical schema migration is required.
- Model/parser configuration IDs remain in provenance for auditability.

## Selection criteria

The selected M2.5 configuration must balance:

- high-risk field precision;
- schema-valid output rate;
- evidence coverage;
- line-item performance;
- latency and throughput;
- peak memory and OOM behavior;
- deployment complexity;
- model and code licenses;
- reproducibility on the selected hardware.

A smaller model wins only when end-to-end review economics and safety are acceptable.

## Not included in M2.5

- fine-tuning;
- custom pretraining;
- automatic regional legal/tax compliance;
- direct ERP posting;
- broad multi-provider fallback;
- autonomous acceptance;
- changing Canonical Invoice v2 to mirror model output.
