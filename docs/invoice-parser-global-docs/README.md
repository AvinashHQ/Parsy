# Global AI Invoice Parser — Rails Documentation Pack

This archive is the implementation source of truth for a small, accurate, fast, and reliable invoice-parsing product built with Ruby on Rails.

The architecture is **global-ready but deliberately not globally certified on day one**. The core accepts visual invoices from any region, normalizes them into a jurisdiction-neutral schema, applies universal arithmetic checks, and loads optional versioned region packs for tax identifiers, tax semantics, structured e-invoice formats, and export mappings.

It intentionally contains no generated Rails project. Generate a clean Rails application, then implement against these contracts and milestone issues.

## Product boundary

The first live MVP is an invite-only, human-in-the-loop workflow:

1. Upload a batch of PDF/image invoices.
2. Detect source format, language, currency, and likely jurisdictions.
3. Prefer deterministic parsing for supported structured e-invoices; otherwise use a managed multimodal model.
4. Normalize output into Canonical Invoice Schema v2.
5. Run universal arithmetic and completeness checks.
6. Run a regional rule pack only when the jurisdiction is known and that pack is benchmarked.
7. Review exceptions.
8. Export canonical JSON, CSV, and XLSX.

Direct ERP posting, tax advice, payments, public signup, and claims of legal compliance are outside the first live MVP.

## Important scope language

Do not market the MVP as “supports every country and every invoice.” Use capability-specific wording:

- **Format accepted:** the system can ingest the file.
- **Fields extracted:** benchmarked extraction coverage for a named profile.
- **Arithmetic validated:** totals and tax sums reconcile.
- **Region validated:** a named, versioned regional rule pack passed its benchmark.
- **Export supported:** a named adapter was tested against a target system/version.
- **E-invoice conformant:** official schema and business-rule validators passed. This is not part of the initial MVP.

## Recommended reading order

1. `00_MASTER_BLUEPRINT.html` — consolidated overview.
2. `docs/01_PRODUCT_BRIEF.md` — problem, wedge, and launch customer.
3. `docs/02_PRD.md` — global-ready MVP requirements.
4. `docs/14_GLOBALIZATION_STRATEGY.md` — canonical core and region-pack strategy.
5. `docs/15_FORMAT_SUPPORT_MATRIX.md` — explicit format capability levels.
6. `docs/03_TECHNICAL_ARCHITECTURE.md` — Rails architecture and processing routes.
7. `docs/04_EXTRACTION_VALIDATION_SPEC.md` — Canonical Invoice v2 and validation rules.
8. `docs/05_SECURITY_PRIVACY.md` — global privacy and data-residency launch gate.
9. `docs/06_EVALUATION_TEST_PLAN.md` — multilingual, multiregion benchmark design.
10. `docs/08_DELIVERY_PLAN.md` — milestones, issue IDs, dependencies, and exit gates.
11. `docs/16_DOCUMENT_AUDIT_AND_DECISIONS.md` — findings from the India-first audit.
12. `docs/17_VALIDATION_REPORT.md` — structural checks, consistency review, and known implementation gaps.
13. Remaining operations, business, ADR, and Rails documents.

## Contracts and reference assets

- `contracts/invoice.schema.json` — Canonical Invoice Schema v2.
- `contracts/openapi.yaml` — initial API contract.
- `contracts/region_profile.schema.json` — contract for versioned rule packs.
- `reference/format_registry.yaml` — source format detection registry.
- `reference/region_profiles.yaml` — example capability profiles; only `global_generic_v1` is required for first live MVP.
- `reference/field_dictionary.yaml` — normalization and risk definitions.
- `reference/validation_rules.yaml` — universal and pack-scoped rule catalogue.
- `reference/database_schema.sql` — conceptual PostgreSQL schema.

## Planning assets

- `planning/mvp_issues.csv` — issue-import-ready backlog grouped by milestone.
- `planning/milestone_exit_gates.csv` — objective release gates.
- `planning/region_backlog.csv` — post-MVP regional expansion queue.
- `invoice_parser_templates.xlsx` — dashboard, issue tracker, scorecard, cost model, capability matrix, and global export templates.

## Initial live-test capability

The first live test should support:

- PDF, JPEG, PNG, and TIFF intake.
- English-language invoices and receipts from multiple countries.
- ISO 4217 currencies, including currencies with 0, 2, and 3 minor units.
- Generic VAT/GST/sales-tax components represented as an array rather than fixed fields.
- Invoice, receipt, credit note, and debit note.
- Header fields, line items, party identifiers, tax breakdowns, payment terms, and references.
- Universal arithmetic, duplicate, date, evidence, and completeness checks.
- Generic CSV/XLSX/JSON export.
- Human approval for all critical/high-risk warnings.

The architecture can accept additional languages and regional packs immediately, but a profile becomes “supported” only after meeting its own holdout-set gate.

## Rails starting point

```bash
ruby -v
rails -v
rails new invoice_parser \
  --database=postgresql \
  --css=tailwind \
  --javascript=importmap
cd invoice_parser
bin/rails db:create
```

Implement in milestone order from `docs/08_DELIVERY_PLAN.md`; do not start with ERP adapters or country-specific tax logic.
