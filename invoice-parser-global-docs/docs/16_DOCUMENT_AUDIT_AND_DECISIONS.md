# Documentation Audit and Decisions

## Audit result

The previous pack was coherent for an India/Tally pilot but was not global-ready. The following assumptions were embedded across product, schema, validation, samples, evaluation, and planning.

## Critical findings and resolutions

| Finding | Risk | Resolution |
|---|---|---|
| Fixed GSTIN fields on supplier/buyer | Cannot represent VAT IDs, EINs, ABNs, UENs, CNPJs, GLNs, or multiple identifiers | Replaced with typed identifier arrays |
| Fixed CGST/SGST/IGST/cess amount fields | Country tax vocabularies contaminate core schema | Replaced with generic tax breakdown arrays |
| Two-decimal money assumption | Incorrect for currencies with 0 or 3 minor units and for high-precision unit prices | Decimal strings plus ISO 4217 minor-unit registry |
| Tally treated as core export | Product appears India-only and ERP-coupled | Generic exports are core; Tally moved to optional adapter |
| Only PDF/image vision path | Wastes cost and loses accuracy on structured e-invoices | Added source sniffing and deterministic structured parsing |
| English/INR/GST golden set | Metrics cannot justify global claims | Added country/language/script/currency/format dimensions |
| India-only privacy section | Cross-border pilots can violate customer requirements | Added global launch checklist, residency, processor, and transfer assessment |
| `place_of_supply`, `IRN`, `UPI` in core | Region-specific concepts become permanent schema baggage | Moved to references, identifiers, extensions, or regional pack |
| Duplicate key based on GSTIN | Poor matching outside India | Generic party identifier/name + number/date/amount/currency/buyer key |
| Model warnings mixed with validation | Unclear source of truth | Separate extraction uncertainty from deterministic validation findings |
| “All regions” implied as one switch | Impossible to verify and risky to market | Introduced capability levels and profile-specific release gates |
| Delivery plan lacked issue traceability | Hard to execute and know when live test is safe | Added milestone issue IDs, dependencies, owners, outputs, and exit gates |

## Documents updated

- Product brief and positioning
- PRD and release blockers
- Technical architecture and processing routes
- Canonical schema and validation spec
- Security/privacy plan
- Evaluation plan and dataset manifest
- Operations runbook
- Delivery plan with issue map
- Business validation and pilot offer
- ADRs and research sources
- Rails implementation guide and codebase map
- OpenAPI, SQL, field dictionary, rules, prompts, samples, and workbook

## Decisions that intentionally remain narrow

- The first live UI is English.
- The first benchmark is English visual invoices across multiple countries/currencies.
- Generic arithmetic is production-gated before regional tax semantics.
- Regional packs are disabled until independently benchmarked.
- Direct accounting-system posting is deferred.
- Certified e-invoice generation/transmission is a separate future scope.

## New unknowns that require evidence

1. Which countries and languages appear in the first two pilot firms' actual batches?
2. How often are line items required versus header-only extraction?
3. What percentage of invoices contain structured XML or machine-readable QR payloads?
4. Which party identifiers and payment fields are operationally necessary?
5. Which export layout produces measurable time savings?
6. What data residency and subprocessor restrictions do pilot firms require?
7. What exact currency/date ambiguity cases occur in the live corpus?

These are milestone M0 issues, not assumptions to hide in implementation.
