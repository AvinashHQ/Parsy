# Extraction, Canonical Data, and Validation Specification

## Canonical Invoice v2

Canonical Invoice v2 is a normalized representation for received invoices and related documents. It is not a legal e-invoice interchange standard and does not replace UBL, CII, Peppol, FatturaPA, NF-e, or a tax authority schema.

## Core groups

### Document metadata

- schema version
- internal document ID
- document type and subtype
- source format family/profile/version
- detected languages/scripts
- jurisdiction candidates and resolution
- original filename hash, page count, and route provenance

### Parties

Each party contains:

- legal/trading/display names
- structured postal address
- ISO country code
- identifiers array
- tax registrations array where necessary
- electronic addresses such as Peppol endpoint IDs
- contact data only when explicitly required by the pilot

Identifier example:

```json
{
  "scheme": "VAT",
  "value": "DE123456789",
  "issuing_country": "DE",
  "purpose": "tax"
}
```

### Document references

Generic typed references include:

- purchase order
- contract
- delivery/despatch advice
- original invoice
- project
- buyer accounting reference
- government/tax platform reference
- custom profile extension

### Monetary totals

Use neutral concepts aligned with common structured standards:

- line extension amount
- allowance total
- charge total
- tax-exclusive amount
- total tax amount
- tax-inclusive amount
- prepaid amount
- rounding amount
- payable amount

Every money value is a decimal string. Currency is carried at document level unless a field explicitly uses tax/accounting currency.

### Tax breakdowns

A document or line can have zero or more tax breakdowns:

- tax type: VAT, GST, SALES_TAX, WITHHOLDING, DUTY, EXCISE, CESS, OTHER
- component/label: e.g. CGST, state tax, city tax
- jurisdiction code
- category code
- rate
- taxable amount
- tax amount
- exemption code/reason
- reverse-charge indicator
- source label

### Lines

- line number
- item/description
- seller and buyer item IDs
- classification identifiers
- quantity and unit code
- unit price and price base quantity
- allowance/charge entries
- line net amount
- tax breakdowns
- line gross/payable amount when printed
- service/delivery period

### Evidence

High-risk fields require a locator:

- JSON pointer-style field path
- page number or structured source path
- short exact text snippet when visual
- optional normalized bounding polygon
- source kind: visual, embedded XML, standalone structured

Evidence snippets are capped and never logged.

### Uncertainties

Extraction uncertainty is separate from validation findings. Examples:

- multiple invoice-number candidates
- ambiguous date order
- unreadable digit
- uncertain currency symbol
- table row split ambiguity
- visual/structured conflict

## Normalization rules

### Dates

- Normalize to ISO `YYYY-MM-DD` only when unambiguous.
- Preserve evidence and raw value.
- Use locale/country hints only as supporting context.
- If `03/04/2026` cannot be resolved, normalized date is `null` and uncertainty is raised.

### Money and rates

- JSON decimal strings only; no binary floating-point.
- Accept up to eight fractional digits in the canonical representation.
- Currency registry defines settlement minor units for tolerance and display.
- Unit prices and rates may require more precision than payable totals.
- Negative values are allowed when consistent with document type and source.

### Country, language, and currency

- Countries: ISO 3166-1 alpha-2.
- Languages: BCP 47.
- Currencies: ISO 4217 alpha code.
- Unknown or unsupported values remain `null` with raw evidence.

### Units and classifications

- Preserve printed unit and classification scheme.
- Normalize to a known code list only when mapping is deterministic.
- Do not relabel HSN as generic HS, or SKU as UNSPSC, without evidence.

## Universal validation rules

### Schema and provenance

- `SCHEMA_INVALID` — output violates v2 schema.
- `UNKNOWN_SOURCE_ROUTE` — route is not approved for the capability profile.
- `MISSING_PROVENANCE` — parser/model/prompt/profile version absent.
- `MISSING_HIGH_RISK_EVIDENCE` — required evidence absent.

### Header arithmetic

When fields exist:

```text
line_extension_amount
- allowance_total
+ charge_total
= tax_exclusive_amount

tax_exclusive_amount
+ total_tax_amount
= tax_inclusive_amount

tax_inclusive_amount
- prepaid_amount
+ rounding_amount
= payable_amount
```

Allow regional profiles to specify whether withholding taxes reduce payable amount or are reported separately.

### Tax arithmetic

- Sum document tax breakdowns and compare with total tax.
- Sum line tax breakdowns and compare with document tax breakdowns when line tax data is complete.
- Check each `taxable_amount × rate` only when the source semantics support it.
- Never derive tax liability when exemptions, compound taxes, inclusive pricing, or withholding semantics are unknown.

### Line arithmetic

When sufficient fields exist:

```text
quantity × unit_price ÷ price_base_quantity
- line_allowances
+ line_charges
= line_net_amount
```

Gross line amounts and taxes are checked separately because invoice standards differ on whether printed line total includes tax.

### Document consistency

- document type versus sign
- issue/due/service-period ordering
- future date policy
- currency code and minor-unit precision
- supplier/buyer presence according to profile
- duplicate probability
- totals present and internally consistent
- line/header completeness agreement

### Duplicate detection

Within a tenant/customer scope, score a duplicate candidate from:

- supplier primary identifier, otherwise normalized supplier name/address key;
- document number;
- issue date;
- currency;
- payable amount;
- buyer identifier;
- source hash.

A probable duplicate is a critical review warning, not automatic deletion.

## Currency tolerance

Default tolerance:

```text
header tolerance = max(1 minor unit, configured absolute override)
line tolerance   = max(1 minor unit, configured line override)
```

Examples:

- JPY: 1
- USD/EUR/INR: 0.01 by ISO minor unit, though a regional/business profile may allow a larger printed-rounding tolerance
- KWD: 0.001

Do not hardcode two decimals or a universal ₹1 tolerance.

## Regional validation

A regional pack may add:

- party identifier format/checksum rules;
- local mandatory fields;
- tax category/component semantics;
- exemption/reverse-charge rules;
- structured e-invoice profile rules;
- regional date/currency constraints;
- local duplicate key fields;
- export mapping prerequisites.

Pack findings include `pack_id` and `pack_version`. Pack failures never mutate canonical data silently.

## Severity

- **CRITICAL:** can cause wrong payable amount, duplicate posting, tenant/security breach, or unsafe export.
- **HIGH:** high-risk field unresolved, jurisdiction pack conflict, or material tax/document inconsistency.
- **MEDIUM:** likely rework but limited direct financial risk.
- **LOW:** formatting/optional-field issue.
- **INFO:** capability or provenance notice.

## Acceptance policy

A document can be auto-accepted only when:

- canonical schema is valid;
- route is approved;
- required high-risk fields/evidence are present;
- no unresolved critical/high finding exists;
- document is in a benchmarked capability profile;
- the measured high-risk precision of that profile is at or above the tenant gate;
- tenant policy does not force review.

All experimental languages and unbenchmarked region packs require review.

## Structured versus visual conflicts

For hybrid invoices:

- Compare document number, issue date, currency, supplier identifier, tax totals, and payable amount.
- If values disagree beyond normalization/tolerance, raise `VISUAL_STRUCTURED_CONFLICT` as critical/high according to field.
- Do not assume the XML or PDF is authoritative without profile-specific rules and operator policy.

## Repair policy

One targeted repair may be requested only for:

- missing/ambiguous field with known page/region;
- schema type mismatch;
- table row alignment issue;
- evidence omission.

Do not repair a deterministic arithmetic mismatch by asking the model to make totals agree. Such mismatches require review or a source re-read with explicit evidence.
