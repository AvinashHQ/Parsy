# Synthetic Corpus Guide

## Purpose

The included corpus is a deterministic functional and regression suite for M2.5-M5. The completed M2 milestone may also reuse its intake/routing fixtures, but open-source model benchmarking belongs to M2.5. Every business entity and identifier is fictitious.

Use it to test:

- upload and file inspection;
- route detection;
- PDF rendering and image normalization;
- canonical-schema validation;
- arithmetic and currency precision;
- tax arrays and withholding representation;
- duplicate detection;
- review queue ranking;
- evidence display;
- immutable approval and export;
- safe quarantine behavior.

Do not use it as the sole evidence for model accuracy. Synthetic layouts are cleaner and less diverse than real accounting documents.

## Corpus layout

- `documents/pdf/` - digital and hybrid PDF invoices.
- `documents/images/` - JPEG, PNG, and multipage TIFF variants.
- `documents/structured/` - synthetic UBL-shaped and unknown XML.
- `documents/unsafe/` - password-protected, corrupt, and extension-mismatch files.
- `ground_truth/` - Canonical Invoice v2 JSON.
- `expected_findings/` - deterministic findings expected after validation.
- `model_outputs/` - good, semantically invalid, OCR-layout, and repair examples.
- `exports/` - approved batch JSONL and normalized CSV.
- `manifest.csv` - authoritative fixture index and SHA-256 values.
- `checksums.sha256` - document checksum list.

## Representative tests

| Fixture | Test |
|---|---|
| `INV-001` | USD and US sales-tax representation |
| `INV-004` | Generic GST components without India-specific core fields |
| `INV-005` | JPY zero-minor-unit handling |
| `INV-006` | KWD three-minor-unit handling |
| `INV-009` | Negative credit-note values |
| `INV-011` | Multipage line-item continuation |
| `INV-013` | Additive VAT plus subtractive withholding |
| `INV-014` | Critical payable mismatch |
| `INV-015` | Required currency missing |
| `INV-016` | Multiple plausible invoice identifiers |
| `INV-017A/B` | Duplicate business invoice with different file identity |
| `IMG-001` | Blur and low resolution |
| `IMG-002` | Rotation normalization |
| `IMG-003` | Phone-photo skew and background |
| `IMG-005` | Multipage TIFF |
| `XML-001` | Recognized UBL-shaped route |
| `XML-002` | Unknown structured profile quarantine |
| `HYB-001` | PDF with embedded structured payload |
| `BAD-001` | Password-protected PDF rejection |
| `BAD-002` | Truncated/corrupt PDF rejection |
| `BAD-003` | MIME and magic-byte mismatch |

## Recommended automated suites

### Intake suite

Run every file in `documents/` and assert route, status, MIME, page count where readable, checksum, and quarantine reason against `manifest.csv`.

### Canonical contract suite

Validate every JSON file in `ground_truth/` against `contracts/invoice.schema.json`.

### Validator suite

Load canonical ground truth and compare finding codes and severities to `expected_findings/`.

### Duplicate suite

Process `INV-017A` and `INV-017B` in either order. The second document must receive `DUPLICATE_CANDIDATE`; neither should be silently discarded.

### Review suite

Build a five-document batch using `INV-002`, `INV-014`, `INV-016`, `INV-017B`, and `IMG-001`. Verify risk ordering, correction, evidence confirmation, approval, immutable revision creation, and export filtering.

### Export suite

Compare approved export output with the files in `exports/`. Ordering rules must be explicit and deterministic.

## Regeneration

`tools/generate_synthetic_corpus.py` regenerates the corpus. Regeneration is a deliberate change: review the diff, increment the corpus version, and update checksums. Never silently replace a fixture used in a benchmark report.
