# Product Brief

## Problem

Accounting teams worldwide receive invoices as digital PDFs, scans, phone photos, receipts, hybrid PDF/XML documents, and jurisdiction-specific structured files. The visible layout, language, tax vocabulary, identifiers, date conventions, currency precision, and downstream accounting format vary by supplier and country.

The operator does not merely need OCR. They need trustworthy normalized data, evidence for risky fields, fast exception handling, and output that fits the existing accounting workflow.

## Product thesis

Build a **global canonical invoice intake and exception workflow**:

1. Accept mixed visual and structured invoice files.
2. Detect the source format and prefer deterministic parsing when structured data is available.
3. Normalize into one jurisdiction-neutral canonical model.
4. Prove universal arithmetic and completeness invariants.
5. Apply a versioned regional rule pack only when its jurisdiction and benchmark are known.
6. Route ambiguous or high-risk fields to human review.
7. Export stable JSON/CSV/XLSX and later add tested ERP adapters.

The moat is not the vision model. It is the normalized contract, capability registry, difficult permissioned dataset, deterministic validation, region-pack system, export mappings, and review telemetry.

## Initial customer

A 2–30 person bookkeeping, accounts-payable, or outsourced accounting team that:

- processes at least 500 supplier invoices or expense documents per month;
- receives documents from multiple suppliers, layouts, or countries;
- currently stages data in spreadsheets or an accounting product;
- can provide 50–100 permissioned difficult documents plus corrected ground truth; and
- accepts a supervised, export-only pilot.

The first cohort should share one operating language—English is recommended—even if invoice countries and currencies vary. Multilingual support is expanded only through benchmarked profiles.

## First live MVP

- Invite-only operator workspace.
- PDF, JPEG, PNG, and TIFF upload; optional ZIP batch.
- Maximum 100 documents per batch and 10 pages per document.
- Invoice, receipt, credit note, and debit note.
- Supplier/buyer, identifiers, addresses, document number/dates, currency, references, totals, generic tax breakdowns, line items, and payment terms.
- Evidence locator for every high-risk field.
- Universal arithmetic, duplicate, date, completeness, and evidence checks.
- Side-by-side exception review.
- Canonical JSON and normalized CSV/XLSX export.
- User-initiated deletion and short automatic retention.

## Not in first live MVP

- Claiming complete support for every jurisdiction or language.
- Tax calculation, tax advice, or legal invoice-validity certification.
- Automatic ledger/account coding.
- Direct accounting-system posting.
- Peppol access-point operation or government portal submission.
- Public signup, subscriptions, payments, email ingestion, or client portal.
- Custom model training or self-hosted GPU inference.

## Capability vocabulary

Each profile is independently labelled:

1. `INGEST_ONLY`
2. `EXTRACTION_BENCHMARKED`
3. `ARITHMETIC_VALIDATED`
4. `REGION_RULES_BENCHMARKED`
5. `EXPORT_ADAPTER_TESTED`
6. `STRUCTURED_CONFORMANCE_VALIDATED`

A country is not “supported” merely because one invoice from that country parsed successfully.

## Success metrics for first live MVP

- Median review time below 45 seconds per document.
- At least 50% reduction in batch completion time against the operator baseline.
- Core header exact match ≥ 97% on clean digital English PDFs.
- Core header exact match ≥ 92% across the complete mixed-quality English holdout.
- Auto-accepted high-risk field precision ≥ 99.5%.
- Zero escaped critical monetary inconsistencies.
- Every output is traceable to a schema, prompt, provider, format profile, and rule-pack version.
- At least two pilot teams request continued access or agree to pay.
