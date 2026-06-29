# Globalization and Region-Pack Strategy

## Goal

Make the product extensible to invoices from any country without turning the core domain model into a union of every tax authority's vocabulary.

“Global” means the architecture can represent and route new countries and formats without destructive schema changes. It does not mean every jurisdiction is legally validated at launch.

## Three-layer model

### Layer 1 — Source format

Answers: what file or structured syntax did we receive?

Examples:

- Visual PDF/image
- OASIS UBL invoice
- Peppol BIS Billing 3.0 UBL/CII
- UN/CEFACT CII
- Factur-X/ZUGFeRD hybrid PDF/XML
- XRechnung
- FatturaPA
- India GST e-invoice JSON
- Brazil NF-e XML

Each source adapter maps to the canonical model and reports parser/version provenance.

### Layer 2 — Canonical invoice

The internal schema contains neutral concepts:

- parties and identifiers;
- addresses and countries;
- document identifiers/dates/references;
- allowances and charges;
- monetary totals;
- tax breakdowns;
- lines and classifications;
- payment terms;
- evidence and uncertainty.

Country-specific concepts are represented through typed arrays and extension values, not top-level hardcoded fields.

### Layer 3 — Region rule pack

A versioned pack adds jurisdiction knowledge:

- identifier validators;
- known tax type/component names;
- mandatory-field profiles;
- allowed code lists;
- currency/tolerance overrides;
- local duplicate keys;
- structured-format business-rule validators;
- export mappings.

The core validation engine invokes packs through a narrow interface and records all decisions.

## Rule-pack interface

A pack must declare:

```yaml
id: eu_vat_core_v1
version: 1.0.0
status: experimental
jurisdictions: [AT, BE, BG, HR, CY, CZ, DE, DK, EE, ES, FI, FR, GR, HU, IE, IT, LT, LU, LV, MT, NL, PL, PT, RO, SE, SI, SK]
supported_languages: [en]
capabilities:
  extraction: benchmarked
  identifier_validation: partial
  tax_semantics: partial
  structured_conformance: none
```

The pack must be deterministic, testable without a model, and disabled by default until its holdout gate passes.

## Pack resolution

Priority order:

1. Tenant-configured profile.
2. Operator-provided country/format hint.
3. Valid structured-format jurisdiction metadata.
4. Agreement between supplier country, buyer country, currency, and identifiers.
5. Otherwise `global_generic_v1`.

Model inference can propose a pack but cannot activate one silently.

## Locale handling

- Store language as BCP 47, such as `en-US`, `de-DE`, or `ar-AE`.
- Store country separately as ISO 3166-1 alpha-2.
- Normalize dates to ISO `YYYY-MM-DD` only when unambiguous; preserve raw evidence.
- Use Unicode CLDR concepts for locale-aware display, but never infer accounting meaning from display formatting alone.
- Store currency as ISO 4217 and use the maintained minor-unit registry for arithmetic tolerance.
- Support right-to-left rendering at the UI layer before claiming Arabic/Hebrew review support.

## Tax representation

Do not put VAT/GST/sales tax fields directly on `amounts`.

Use:

```json
{
  "tax_type": "VAT",
  "component": null,
  "jurisdiction_code": "DE",
  "category_code": "S",
  "rate": "19",
  "taxable_amount": "100.00",
  "tax_amount": "19.00",
  "exemption_reason": null
}
```

India-specific CGST/SGST/IGST values use `tax_type: GST` with components. US state/local taxes use separate jurisdiction/component rows. Withholding taxes use negative or explicitly typed breakdowns according to the canonical rules.

## Structured-format strategy

- First sniff namespaces/root elements and embedded PDF attachments.
- Run official XSD/Schematron validators where licensing and distribution permit.
- Map structured data deterministically; do not spend model tokens on already structured values.
- Preserve source profile identifiers and validation artefact versions.
- When visual and structured values disagree, raise `VISUAL_STRUCTURED_CONFLICT`; do not choose silently.
- Treat e-invoice generation and network transmission as separate products from document ingestion.

## Expansion sequence after the generic MVP

1. Generic English visual invoices across multiple currencies and countries.
2. India GST pack and Tally adapter if pilot demand exists.
3. Peppol/EN 16931 read-only ingestion and validation.
4. UK/EU VAT extraction profiles.
5. US/Canada sales-tax extraction profile.
6. Australia/New Zealand and Singapore Peppol profiles.
7. Country-native formats such as FatturaPA and Brazil NF-e.
8. Additional languages/scripts based on customer demand and benchmark data.

## Definition of regional support

A region profile can be published only when:

- permissioned evaluation data covers at least the required document classes and vendors;
- high-risk field precision passes its gate;
- identifier and arithmetic rules have deterministic tests;
- all mandatory locale/currency edge cases pass;
- docs state unsupported scenarios;
- an operator can override detection;
- the profile has a named owner and update cadence.
