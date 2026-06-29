# Pilot Profile v1 — `global_generic_v1`

**Status:** Frozen for M1  
**Evidence status:** synthetic planning assumption  
**Profile version:** `global_generic_v1.0`

## Target user

English-speaking bookkeeping and AP operators processing heterogeneous supplier invoices in batches.

## Workflow

1. Upload a visual-document batch.
2. Inspect and classify each document.
3. Extract into `canonical_invoice_v2`.
4. Run universal deterministic validations.
5. Review evidence-backed exceptions.
6. Approve or reject a revision.
7. Export approved data as XLSX/CSV/JSON.

## Pilot teams

### Pilot Alpha

- outsourced bookkeeping team;
- approximately 1,800 documents/month;
- predominantly USD, GBP, EUR and AUD;
- digital PDF and scan-heavy;
- downstream workflow: QuickBooks Online plus Excel staging;
- required profile: header, parties, references, totals and summary tax;
- line items not required for initial trial.

### Pilot Beta

- outsourced AP team;
- approximately 3,200 documents/month;
- predominantly GBP, EUR, SGD and INR;
- mixed PDFs, scans and images;
- downstream workflow: Xero/CSV staging;
- required profile: header and totals for all documents; line items for a defined subset;
- line items remain human-reviewed.

Names are pseudonymous because this is a planning scenario.

## Supported input

- PDF, JPEG, PNG and TIFF
- maximum 10 pages/document
- maximum 100 documents/batch
- flat ZIP accepted only after archive-safety inspection

## Supported document types

| Type | Status |
|---|---|
| Invoice | Primary |
| Credit note | Primary |
| Receipt | Secondary, review-required |
| Debit note | Secondary, review-required |
| Unknown business document | Quarantine |

## First-live language and geography

- English text
- Latin script
- multiple supplier/buyer countries
- ISO currency handling independent of country

No country is marketed as fully compliant merely because its invoices are in the corpus.

## Required output

- workbook with Invoice, Parties, Identifiers, TaxBreakdowns and LineItems sheets;
- equivalent CSV bundle;
- canonical JSON;
- warning and review status columns;
- schema, extraction, validation and profile versions.

## Human responsibility

Every document requires approval during the initial live test. M1 does not implement an auto-accept policy. M3 may introduce profile-gated acceptance only after M2 benchmark evidence.

## Explicit exclusions

- direct posting;
- tax calculation or tax advice;
- ledger/account classification;
- multilingual guarantee;
- government submission;
- Peppol access-point behavior;
- public signup and billing;
- training on pilot data without separate permission.
