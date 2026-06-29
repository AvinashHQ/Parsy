# Global Edition Changelog

## 2026-06-28

### Reframed

- Replaced “Indian accounting firms” positioning with a global-ready invoice workflow.
- Separated universal extraction/arithmetic capability from jurisdiction-specific compliance capability.
- Reclassified Tally as an optional India export adapter rather than a core product requirement.

### Schema changes

- Replaced fixed `gstin`, `cgst`, `sgst`, `igst`, `cess`, `hsn_sac`, and `place_of_supply` fields with generic identifier, tax-breakdown, classification, jurisdiction, and reference arrays.
- Changed monetary values to decimal strings and currency-aware precision.
- Added structured addresses, BCP 47 language tags, ISO 3166 country codes, source-format metadata, document references, allowances/charges, service periods, payment terms, and evidence locators.
- Added explicit extraction uncertainties separate from deterministic validation warnings.

### Architecture changes

- Added deterministic source-format detection before multimodal extraction.
- Added structured parser adapters for UBL/CII-family documents as an incremental path.
- Added versioned region-rule packs and capability registry.
- Added per-profile acceptance gates and no-fallback rules for unapproved processors.

### Planning changes

- Replaced phase-only delivery notes with milestone and issue IDs suitable for GitHub/Jira import.
- Added objective exit gates for the first live MVP.
- Added a post-MVP regional expansion backlog.

### Evaluation changes

- Expanded dataset dimensions to country, language, script, currency minor unit, tax regime, structured format, document type, quality, and vendor holdout.
- Added capability-level metrics and profile-specific release gates.
