# Samples

The root samples demonstrate Canonical Invoice v2 and generic normalized exports.

- `canonical_invoice.json` — EUR/VAT-style visual invoice represented generically.
- `canonical_invoice_jpy.json` — zero-minor-unit currency case.
- `Invoices.csv`, `Parties.csv`, `PartyIdentifiers.csv`, `TaxBreakdowns.csv`, `LineItems.csv` — relational flat export.
- `adapters/india_tally/` — legacy illustrative India adapter retained as optional reference, not a core MVP output or import guarantee.

All examples are synthetic. Regional/ERP samples become supported only after adapter-specific tests.
