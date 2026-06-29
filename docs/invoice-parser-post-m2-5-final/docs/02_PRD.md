# Product Requirements Document

## Core user story

As a bookkeeping or accounts-payable operator, I upload a batch of supplier documents from different layouts and countries, review only risky records, and download normalized data without retyping every field.

## Product principles

- Global canonical core; regional behavior is plug-in and versioned.
- Structured data before vision extraction.
- Unknown is preferable to a fabricated value.
- Arithmetic truth before model confidence.
- Capability claims are profile-specific and evidence-based.
- Human approval before downstream posting.

## Functional requirements

### Intake and format routing

- Accept PDF, JPEG, PNG, and TIFF in the live MVP.
- Sniff MIME type and magic bytes; do not trust extensions.
- Reject corrupt, encrypted, oversized, decompression-bomb, or unsupported files with an actionable reason.
- Compute SHA-256 before model processing.
- Detect embedded files in PDF. When a recognized Factur-X/ZUGFeRD XML payload is present, route it through the structured parser and retain the visual PDF as evidence.
- Detect standalone XML root namespaces and route supported UBL/CII profiles deterministically. Unknown XML is quarantined as `UNSUPPORTED_STRUCTURED_FORMAT`, never sent blindly to the vision path.
- Treat one uploaded file as one business document unless a benchmarked splitter profile is selected.
- Store detected source format, version, language candidates, script, and page count.

### Extraction

- Return only Canonical Invoice Schema v2 output.
- Preserve normalized values and evidence snippets; do not copy the complete document text into the database.
- Represent money as decimal strings, not JSON floating-point values.
- Use ISO 4217 currency codes where identifiable.
- Use ISO 3166-1 alpha-2 country codes and BCP 47 language tags where identifiable.
- Represent party identifiers as `{scheme, value, issuing_country}` records rather than fixed country fields.
- Represent taxes as an array of generic tax breakdowns.
- Represent item classifications as an array; schemes may include HS, HSN, SAC, UNSPSC, SKU, or country-specific codes.
- Distinguish invoice, receipt, credit note, debit note, pro forma, self-billed invoice, and unknown where possible.
- Store ambiguity in `uncertainties`; do not convert ambiguity into a confident value.

### Universal validation

- Parse all decimal strings with `BigDecimal`.
- Derive tolerance from the currency minor unit registry, with profile overrides.
- Recompute line net amounts, document allowances/charges, tax-exclusive total, tax-inclusive total, prepaid amount, rounding, and amount due when sufficient fields exist.
- Reconcile tax-breakdown sums with total tax.
- Validate credit/debit sign consistency against document type.
- Flag ambiguous normalized dates, future issue dates, implausibly old dates, unsupported currency codes, missing high-risk evidence, and impossible quantities/rates.
- Detect probable duplicates within a tenant using supplier identifier/name, document number, issue date, payable amount, currency, and buyer identifier.

### Regional validation

- Resolve a rule pack from explicit tenant profile, seller/buyer countries, structured format, and operator confirmation.
- Never silently apply a jurisdictional pack based only on model inference.
- Store pack name, version, resolution reason, and capability status.
- If no benchmarked pack applies, run `global_generic_v1` and label the result `REGION_RULES_NOT_APPLIED`.
- Regional validators may validate identifier checksum/format, tax component semantics, mandatory fields, code lists, and local rounding rules. They must not provide tax advice.

### Review

- Show source and structured fields on one screen.
- Show detected language, currency, source format, jurisdiction, applied rule pack, and capability level.
- Sort warnings by financial and posting risk.
- Let the operator override country/locale/rule-pack detection.
- Record changed field paths, old/new value hashes, actor, reason, and timestamp without duplicating source content.
- Require explicit approval for critical/high warnings.
- Support keyboard-first save, approve, reject, and next-exception actions.

### Export

- Generate Canonical JSON v2.
- Generate normalized `Invoices.csv`, `Parties.csv`, `PartyIdentifiers.csv`, `TaxBreakdowns.csv`, and `LineItems.csv` plus equivalent XLSX sheets.
- Allow a tenant-configured flat export mapping after generic export is stable.
- Keep Tally, QuickBooks, Xero, SAP, NetSuite, and country portal formats as separately tested adapters.
- Never emit arbitrary SQL against an unknown customer database.
- Include stable document, party, tax, and line IDs.

### Retention

- Allow immediate batch deletion.
- Default pilot retention: raw files ≤ 24 hours after completed review/export; generated exports ≤ 7 days.
- Make retention configurable only within an administrator-approved policy.
- Record content-free purge evidence and object-store reconciliation status.

## Non-functional requirements

- p95 processing under 25 seconds for a typical one-page visual invoice, excluding queue delay.
- Structured invoice parsing p95 under 3 seconds for files below configured size.
- One document failure never fails a batch.
- At-least-once job execution with domain idempotency.
- No source document body, full identifiers, addresses, bank details, or model response in logs or error payloads.
- Unicode-safe storage, display, search, and export.
- Time stored in UTC; document dates remain date-only values.
- Schema, prompt, parser, model, format registry, currency registry, and rule-pack versions stored per result.
- First live pilot target: 100 documents per batch and 1,000 documents/day per tenant.

## Roles

- `OPERATOR`: upload, review, approve, export, delete.
- `ADMIN`: invite operators, configure tenant profile, retention, allowed regions, and export mapping.

Fine-grained client permissions and public self-service are deferred.

## Primary screens

1. Batch upload and locale/profile hints.
2. Batch progress and per-document route/status.
3. Risk-ranked review queue.
4. Document review/editor.
5. Export and deletion confirmation.
6. Pilot metrics and capability dashboard.

## Release blockers

The MVP cannot go live when any of these remain true:

- Canonical schema is still country-specific.
- Currency precision is fixed at two decimals.
- Unrecognized structured XML can reach a model without quarantine.
- High-risk values lack evidence.
- Profile and rule-pack versions are not persisted.
- A critical monetary mismatch can be auto-approved.
- Deletion verification and restore testing are incomplete.
