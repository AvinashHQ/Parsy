# Product Brief — M0 Approved

**Status:** Approved for M1  
**Profile:** `global_generic_v1.0`  
**Schema target:** `canonical_invoice_v2`

## Problem

Bookkeeping and AP operators spend material time re-keying and validating heterogeneous supplier invoices before staging data for their existing accounting systems. The hard problem is not text recognition alone; it is producing evidence-backed, normalized data that reconciles and can be reviewed quickly.

## Initial customer

A 2–30 person bookkeeping, AP or outsourced-accounting team processing at least 500 supplier documents per month, using English as the operating language and spreadsheets/import templates as part of the workflow.

## First job to be done

> Upload a batch of visual supplier invoices, review risk-ranked evidence and deterministic findings, then export approved normalized data to XLSX/CSV.

## First-live scope

- PDF/JPEG/PNG/TIFF; inspected flat ZIP optional
- invoice and credit note primary; receipt/debit note review-required
- English/Latin script
- multiple countries and ISO currencies
- parties, invoice metadata, references, totals, generic taxes and conditional line items
- evidence for high-risk values
- universal arithmetic, duplicate, completeness and file-policy checks
- supervised approval
- JSON/CSV/XLSX export
- short explicit retention

## Excluded

Direct posting, ledger coding, tax advice, worldwide compliance claims, public signup, billing, email ingestion, multilingual guarantee and model training on pilot data.

## Baseline and success target

Assumed median baseline is 5.6 active minutes/document, with 4.2 minutes for header/totals and 9.1 minutes when line items are required. The live MVP target remains at least 50% reduction in batch completion time with zero escaped critical monetary errors.

## Product thesis

A country-neutral canonical contract plus deterministic validation, evidence-backed review and correction telemetry creates more durable value than a model-only parser.

## Decision

Proceed to M1. The first implementation is the canonical contract and deterministic core; model extraction and review UI follow only after the contract passes its milestone gate.
