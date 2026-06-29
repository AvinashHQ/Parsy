# M0 Interview Synthesis

> Synthetic planning scenario. Do not cite as real customer evidence.

## Cohort

Seven qualifying interviews across five organizations:

- three bookkeepers/AP operators observed directly;
- one reviewer;
- two team leads/AP leads; and
- one firm owner.

The sample covered visual invoices from multiple supplier countries, seven currencies, header-only and line-item workflows, spreadsheet staging, QuickBooks Online, Xero and generic ERP CSV import.

## Confirmed hypotheses

### H1 — Review time is the dominant adoption metric

**Confirmed.** Operators cared more about how quickly they could verify and correct a batch than raw field-level extraction claims.

### H2 — Generic reviewed exports create value before direct integrations

**Confirmed.** Six of seven considered a controlled XLSX/CSV export useful. Five were willing to test it without direct posting.

### H3 — Arithmetic and evidence warnings improve trust

**Confirmed.** Operators consistently requested a visible source location for invoice number, dates, tax and totals. Arithmetic inconsistencies should block export.

### H4 — The first paid expansion will be one regional or ERP capability

**Mixed but directionally supported.** Requests clustered around QuickBooks/Xero mapping and regional tax checks, but no single expansion won decisively. Do not build one in M1.

### H5 — Short explicit retention is acceptable

**Confirmed for a supervised pilot**, provided deletion is explicit, source content is absent from logs, processors are disclosed and evaluation reuse requires separate permission.

## Workflow conclusion

The MVP should optimize the segment between document intake and reviewed import-ready data. The product should not attempt ledger coding, posting, payment approval or tax filing.

## Scope conclusions

- Header/totals are the universal first-live profile.
- Line items are conditional and initially review-only.
- English/Latin script is the benchmarked language profile.
- Multi-currency support is required from the canonical core.
- Regional tax labels must not become universal schema fields.
- Credit notes must be differentiated from invoices before export.
- Evidence and deterministic findings are product requirements, not optional debugging metadata.

## Commercial signal

The measurable value unit is **operator minutes saved per approved document**, with batch completion time as the secondary metric. Pricing should not be finalized until M5 captures model cost, review time and support overhead.
