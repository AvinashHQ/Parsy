# M0 Decision Record

**Status:** Approved for M1  
**Decision date:** 2026-06-29  
**Applies to:** `canonical_invoice_v2`, `global_generic_v1`

## Binding product decisions

### 1. Product wedge

The first product is a supervised batch-processing workflow, not an API-only parser and not an autonomous bookkeeper.

### 2. Customer

The first customer is a 2–30 person bookkeeping, AP or outsourced-accounting team processing at least 500 heterogeneous documents per month.

### 3. First-live operating language

English, with Latin-script source documents. Country and currency may vary.

### 4. Input boundary

Supported for the first pilot:

- PDF
- JPEG
- PNG
- TIFF
- optional flat ZIP batch after archive-safety inspection

Structured XML or hybrid payloads may be detected, but unsupported profiles are quarantined rather than silently converted.

### 5. Document boundary

- `invoice`: supported
- `credit_note`: supported
- `receipt`: review-required/secondary
- `debit_note`: review-required/secondary
- statements, purchase orders, delivery notes, pro-forma invoices and handwritten-only documents: unsupported in first live test

### 6. Data boundary

Header, party, reference, currency, totals and evidence fields are mandatory where present. Tax breakdowns are represented generically. Line items are conditional per pilot profile and remain review-required initially.

### 7. Safety boundary

No critical or high-severity deterministic finding may auto-accept. M1 implements findings but does not enable auto-acceptance.

### 8. Export boundary

Approved revisions produce:

- canonical JSON;
- normalized XLSX workbook; and
- normalized CSV bundle.

Direct posting, tax filing and ledger coding are excluded.

### 9. Global architecture boundary

Country-specific identifiers and tax concepts must be represented through typed generic collections or versioned regional profiles. No country-specific database columns may enter the canonical core.

### 10. Commercial boundary

The MVP proves reduced operator touch time and safe reviewed output. It does not need billing, public signup, email ingestion or a client portal.

## Reversible after evidence

- exact retention durations;
- first hosting region;
- first AI provider;
- line-item coverage percentage;
- first ERP export adapter; and
- first regional rule pack.

## Requires a new decision record

- adding direct accounting-system posting;
- introducing unattended exports;
- changing high-risk acceptance policy;
- adding a jurisdiction compliance claim;
- changing canonical schema major version; or
- retaining source documents for training/evaluation beyond signed permission.
