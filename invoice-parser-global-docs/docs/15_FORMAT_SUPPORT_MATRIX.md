# Format and Region Support Matrix

## Capability levels

| Level | Meaning |
|---|---|
| L0 | File rejected or quarantined safely |
| L1 | File can be ingested and previewed |
| L2 | Canonical fields are extracted and benchmarked |
| L3 | Universal arithmetic and completeness checks run |
| L4 | Regional identifiers/tax semantics are benchmarked |
| L5 | Export adapter is tested against a named target/version |
| L6 | Official structured-format conformance validation passes |

## First live MVP commitment

| Input family | MVP level | Route | Notes |
|---|---:|---|---|
| Digital PDF | L3 | visual/text + multimodal | English benchmark required |
| Scanned PDF | L3 | render + multimodal | quality warnings required |
| JPEG/PNG | L3 | multimodal | orientation and resolution checks |
| TIFF | L3 | normalize pages then multimodal | bounded page count |
| Factur-X/ZUGFeRD PDF | L1 initially, L3 target | extract embedded XML if recognized | conflict check before L3 claim |
| Standalone UBL/CII XML | L1 initially, L3 target | deterministic parser | unsupported profile quarantined |
| JSON from tax portals | L0 initially | quarantine | add only through named adapter |
| Spreadsheet invoices | L0 | reject | not an invoice interchange standard in MVP |
| Password-protected PDF | L0 | reject with guidance | never attempt password cracking |
| Email body/attachment ingestion | L0 | not accepted | deferred |

## Regional capability at first live test

| Profile | Extraction | Arithmetic | Regional rules | Export | Launch status |
|---|---|---|---|---|---|
| `global_generic_v1` | English visual invoices | Yes | No legal/tax semantics | Generic JSON/CSV/XLSX | Required |
| `india_gst_v1` | Existing reference data | Experimental | GST identifier/components | Tally draft optional | Not a launch dependency |
| `eu_vat_core_v1` | Data collection needed | Generic only | Experimental | Generic only | Post-MVP |
| `us_sales_tax_core_v1` | Data collection needed | Generic only | Experimental | Generic only | Post-MVP |
| `peppol_billing_3_read_v1` | Structured only | Yes | EN 16931/Peppol validators | Canonical only | Post-MVP |
| `fatturapa_read_v1` | Structured only | TBD | Official validation artefacts | Canonical only | Backlog |
| `brazil_nfe_read_v1` | Structured only | TBD | Official schema/rules | Canonical only | Backlog |

## Language support policy

A model may technically read many languages, but production support is benchmarked per language/script profile.

First live test:

- UI: English.
- Documents: English primary; non-English documents may be processed only as experimental and must always require review.
- Unicode: fully preserved.
- Right-to-left document review: not claimed until the UI and evaluator are tested.

## Format-adapter acceptance gate

A structured adapter must:

- identify exact syntax/profile/version;
- validate safely or report validation unavailable;
- map all required canonical fields deterministically;
- preserve unmapped source paths in diagnostics, not the canonical schema;
- handle credit notes and negative amounts;
- detect visual-versus-structured conflicts for hybrid files;
- have official sample/regression fixtures where redistribution is permitted.
