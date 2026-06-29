# Error and Exception Taxonomy

## Severity

| Severity | Definition | Examples |
|---|---|---|
| CRITICAL | Can cause material financial loss, duplicate payment, regulatory exposure or incorrect posting without likely detection | Wrong payable total, wrong currency, duplicate invoice accepted, credit note treated as invoice |
| HIGH | Causes incorrect accounting/tax outcome or blocks import and requires expert correction | Wrong tax amount/type, wrong supplier, incorrect invoice number linked to payment, missing required line item |
| MEDIUM | Requires rework but is usually detectable before posting | Date format, missing PO reference, minor line description issue |
| LOW | Cosmetic or low-impact inconsistency | Capitalization, harmless whitespace, nonessential formatting |

## Categories

| Code | Category | Examples |
|---|---|---|
| SOURCE_QUALITY | Poor source quality | Blur, crop, skew, handwriting, low contrast, unreadable characters |
| FILE_HANDLING | File/preparation error | Wrong split, missing page, merged invoices, corrupted upload |
| DOC_CLASS | Document classification | Invoice vs receipt vs credit/debit note vs statement |
| PARTY | Supplier/buyer identity | Wrong entity, alias mismatch, branch confusion |
| IDENTIFIER | Identifier/reference | Tax ID, registration number, PO, contract, invoice number |
| DATE | Date/time | Issue date, due date, service period, locale ambiguity |
| CURRENCY | Currency | Wrong ISO code, symbol ambiguity, mixed currency |
| AMOUNT | Monetary amount | Subtotal, payable, prepaid, rounding, sign |
| TAX | Tax representation | Type, component, jurisdiction, rate, amount, exemption, withholding |
| LINE_ITEM | Line data | Description, quantity, unit, unit price, discount, line total |
| CLASSIFICATION | Product/account classification | HSN/SAC, SKU, ledger, tax code, cost centre |
| DUPLICATE | Duplicate handling | Repeated invoice, amended copy, same invoice across channels |
| ARITHMETIC | Reconciliation | Lines do not sum, tax mismatch, total mismatch |
| EXPORT_MAPPING | Output mapping | Wrong column, format, decimal/date convention, import code |
| SYSTEM_ENTRY | Manual/system entry | Typo, pasted into wrong field, stale master data |
| REVIEW_ESCAPE | Review failure | Existing error missed or incorrectly approved |
| PERMISSION | Access/approval | Wrong user, missing approval, unauthorized document handling |
| OTHER | Other | Explain clearly |

## Root-cause tags

- `SOURCE_AMBIGUOUS`
- `OPERATOR_ENTRY`
- `MASTER_DATA`
- `PROCESS_GAP`
- `SYSTEM_LIMITATION`
- `IMPORT_TEMPLATE`
- `SUPPLIER_ERROR`
- `CUSTOMER_RULE`
- `UNKNOWN`

## Product-response tags

- `AUTOMATE`
- `DETECT`
- `HIGHLIGHT_EVIDENCE`
- `REQUIRE_CONFIRMATION`
- `BLOCK_EXPORT`
- `OUT_OF_SCOPE`
