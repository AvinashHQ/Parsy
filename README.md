# Parsy — AI Invoice Parser

Rails 8.1 modular monolith for a supervised, invite-only invoice intake and exception-review MVP.

Parsy normalizes invoices into Canonical Invoice Schema v2, routes visual/structured inputs safely, keeps evidence attached to review decisions, exports only approved revisions, and enforces tenant-scoped security controls before live pilot use.

## Current milestone status

The retained executable evidence lives in `test/fixtures/files/invoice_parser/samples/`; broad historical product docs were intentionally removed from the app repo.

| Milestone | Status | Current evidence |
| --- | --- | --- |
| M0 — Pilot contract and scope freeze | Complete, owner-declared | GitHub milestone has no open issues |
| M1 — Canonical contract and deterministic core | Complete | Canonical schema/domain/currency/validator/export tests |
| M2 — Safe intake and reproducible extraction | Complete | Upload inspection, routing, provider contract, repair, provenance, and structured-adapter tests |
| M2.5 — Open-source extraction upgrade | Complete | Local parser/semantic route/benchmark tests over the final synthetic corpus manifest |
| M3 — Human review and safe acceptance | Complete | Review workflow, 50-document keyboard system flow, immutable approval, and approved-only export tests |
| M4 — Security, privacy, reliability, deployment | Complete | Tenant isolation, private storage, purge, content-free logging, quota, restore, privacy, production config, upload-abuse, Brakeman, and dependency-audit gates |
| M4.5 — Cloud extraction and database delivery | Complete | Cloud vision extraction (Gemini, ADR-026) verified end-to-end on main; external database delivery (destinations, schema introspection, system-derived mappings, approval-gated idempotent push) merged with unit + live-PostgreSQL integration coverage |
| M5 — Closed live MVP test | Planned | Pilots the M4.5 flow; requires real supervised pilot operating evidence |
| M6 — First demanded regional capability | Deferred | Chosen only after M5 demand evidence |

Boundary: M0-M2 include owner-declared/product evidence plus implemented regressions where present. M2.5-M4 are backed by current automated tests. Real production hosting, real customer corpus accuracy, and closed-pilot operating metrics remain M5 evidence, not M4 evidence.

## Implemented capabilities

- Canonical Invoice Schema v2 value objects, schema validation, deterministic decimal/currency handling, universal validation, duplicate fingerprinting, and JSON/CSV/XLSX exporters.
- Secure intake inspection for PDFs, images, XML, JSON, unsafe filenames, encrypted/corrupt/oversized PDFs, XML entity risks, and upload-abuse edge cases.
- Structured XML routing for synthetic UBL/CII-style fixtures and safe quarantine for unknown structured payloads.
- Hybrid PDF/XML detection for embedded invoice XML attachments, including the final-docs `HYB-001` sample.
- Local extraction contract and M2.5 benchmark harness over the final synthetic corpus manifest.
- Review batches/documents/revisions/findings/evidence, risk queue, high-risk evidence focus, locale/profile overrides, immutable approved revisions, and approved-only exports.
- Invite/operator-token authentication, tenant-scoped controllers, private Active Storage export downloads, retention purge evidence, restore verification, privacy launch checks, spend guard/circuit breaker, and production security config invariants.
- External database delivery (M4.5): tenant-scoped destination connections with encrypted credentials, connection tests, `information_schema` introspection, system-derived field mappings with one-time operator confirmation, and approval-gated idempotent pushes with per-document provenance and retry.

## Retained sample fixture coverage

The retained sample package lives at:

```text
test/fixtures/files/invoice_parser/samples/
```

Automated sample coverage:

- `test/services/evaluation/final_docs_samples_test.rb`
  - validates `canonical_invoice.json` and `canonical_invoice_jpy.json` against Canonical Invoice Schema v2;
  - round-trips root canonical samples through the JSON exporter;
  - reconciles root flat CSV samples (`Invoices.csv`, `Parties.csv`, `PartyIdentifiers.csv`, `TaxBreakdowns.csv`, `LineItems.csv`) against `canonical_invoice.json`;
  - verifies all 29 synthetic corpus source files exist, match manifest SHA-256 checksums, and route through `Intake::UploadInspector` as documented;
  - validates all 25 synthetic ground-truth canonical JSON files and parses every expected-finding JSON file;
  - maps the actual `XML-001` structured sample, quarantines `XML-002`, and parses the optional illustrative Tally JSON/XML adapter samples.
- `test/services/evaluation/m2_5_benchmark_runner_test.rb`
  - runs the M2.5 synthetic manifest contract and records synthetic metrics separately from real-corpus claims.
- `test/services/intake/upload_inspector_test.rb`
  - protects existing visual, image, structured, hybrid, encrypted, corrupt, and unknown-format routing behavior.

Run the focused sample gate:

```bash
ruby bin/rails test test/services/evaluation/final_docs_samples_test.rb
```

Run the focused intake regression gate:

```bash
ruby bin/rails test test/services/intake/upload_inspector_test.rb
```

## Prerequisites

- Ruby 3.4.8. On this workstation Ruby is managed by mise; run Rails through `ruby bin/rails ...`.
- PostgreSQL available locally.
- Bundler.
- Chrome/Chromium for Selenium system tests.
- AWS S3 credentials only when exercising production/private object storage outside local disk-backed development/test.

## Local setup

```bash
bundle install
cp .env.example .env
brew services start postgresql@16
ruby bin/rails db:prepare
```

## Extraction provider (M4.5)

`PARSY_EXTRACTION_PROVIDER` selects the semantic extraction backend (ADR-026):

- Unset, `gemini`, or `cloud` — Google Gemini, the MVP default. Requires `GEMINI_API_KEY` (see `.env.example`); read from ENV only, never committed or logged.
- `ollama`, `local`, or `local_open_source` — the local `qwen3-vl:4b` fallback via Ollama.
- Any other value fails safe (`Extraction::DocumentExtractor::INVALID_PROVIDER`) rather than silently guessing a provider.

`bin/dev` loads `.env` automatically via foreman; `bin/rails console`/`runner`/`test` need the `dotenv-rails` gem (already a dependency) or the variables exported in your shell.

## Create a local operator

The app is invite/operator-token gated. Seeds are intentionally empty, so create a development tenant and operator in the Rails console:

```bash
ruby bin/rails console
```

```ruby
tenant = Tenant.find_or_create_by!(slug: "demo") do |record|
  record.name = "Demo Tenant"
  record.hosting_region = "local"
  record.storage_region = "local"
  record.allowed_providers = ["fixture"]
  record.allowed_processing_regions = ["local"]
  record.monthly_spend_limit_cents = 10_000
  record.current_spend_cents = 0
  record.circuit_breaker_status = "closed"
end

user = User.find_or_initialize_by(tenant: tenant, email: "operator@example.test")
user.name = "Demo Operator"
user.role = "operator"
user.operator_token = "dev-token"
user.save!

Review::Batch.find_or_create_by!(tenant: tenant, name: "Demo batch") do |batch|
  batch.status = "uploaded"
end
```

Use `operator@example.test` and `dev-token` on the sign-in screen.

## Run the app

```bash
bin/dev
```

Then open:

```text
http://localhost:3000
```

Routes:

- `/session/new` — operator-token sign in.
- `/review/upload/new` — operator ZIP/PDF/image/XML intake.
- `/review/batches` — tenant-scoped batch list.
- `/review/batches/:id` — batch progress, risk queue, exports, and the "Push to database" panel.
- `/review/documents/:id` — evidence-backed document review/editor.
- `/destinations/connections` — external delivery databases: connect, test, schema capture, mapping review/confirm.
- `/up` — health check.

Current UI scope: authenticated upload, review, approval, export, and approval-gated external-database push.

## Using the app

A typical end-to-end session, once you're signed in:

1. **Upload invoices** at `/review/upload/new`. Pick a single PDF/image/XML file, or a ZIP archive for bulk intake. Name the batch and submit — you land on the batch page.
2. **Wait for extraction.** Each document runs cloud vision extraction (Gemini) in the background. The batch page live-updates as documents move `uploaded` → `extracting` → `needs_review` / `ready_for_approval`.
3. **Review and approve** at `/review/documents/:id`. Check extracted fields against the evidence panel (source text/bounding boxes), correct anything wrong, then approve. Unresolved high-risk findings require an explicit confirmation before a document can be approved.
4. **Deliver the approved data** from the batch page — either or both:
   - **Export a file**: click JSON, CSV, or XLSX to download the approved revisions.
   - **Push to a database**: once at least one destination has a confirmed mapping (see below), a **Push to database** button appears next to Export. Pick the destination and push; the batch page shows push history and lets you retry any failed documents.

## External database delivery (M4.5)

Approved invoices can be pushed directly into an operator-configured external database (PostgreSQL or MySQL) — no manual export/import step. The design splits intelligence from execution so arbitrary vendor schemas stay reliable:

1. **Schema understanding — once per destination.** The operator connects the customer database (credentials encrypted at rest via Active Record Encryption, ENV-keyed), tests it, and captures its real schema through `information_schema` introspection. The system then derives the canonical→target column mapping itself: deterministic name/synonym heuristics first, then a Gemini proposal over schema **metadata only** (column names/types — never invoice content; tenant-gated with a heuristic-only fallback). The operator reviews and confirms the mapping once; validation blocks confirmation on missing columns, type mismatches, unfed NOT NULL columns, or unmapped `document_id`/`line_id` keys.
2. **Conversion + insert — every push, deterministic.** "Push to database" on a batch is an explicit operator action (ADR-027 — never an automatic side effect) that runs a background job writing only approved revisions through confirmed mappings: typed coercion per the introspected column types, pre-insert validation, per-invoice transactions, parameterized SQL with quoted identifiers, and idempotent upserts keyed on the mapped `document_id` column (re-pushes update in place; line rows are replaced atomically). Per-document results, counts, and terminal status (`pushed`/`partial`/`failed`) are recorded content-free, with retry for failed documents only.

### Setting up a destination (one-time, per database)

1. Go to `/destinations/connections` → **New destination**.
2. Fill in the connection details — label, engine (PostgreSQL or MySQL), host, port, database name, username, password — and save. Credentials are encrypted at rest and never rendered back once saved; leave username/password blank on a later edit to keep the stored values.
3. Click **Test connection** to confirm Parsy can reach the database before going further.
4. Click **Capture schema** to introspect the database's real tables and columns.
5. For each canonical table you want to fill (`invoices`, `line_items`), click **Propose mapping**. Parsy matches columns by name/synonym first, then asks Gemini to resolve any remaining columns using schema metadata only — never invoice content.
6. Review the proposed mapping and adjust anything wrong, then click **Confirm**. A mapping only confirms once every required field is mapped and types are compatible; the page explains exactly what's blocking confirmation otherwise.
7. The destination now appears in the **Push to database** picker on every batch page.

### Testing locally without a real customer database

Spin up a scratch PostgreSQL database with an intentionally different schema to exercise the full mapping and push flow end to end:

```bash
createdb parsy_test_customer
psql -d parsy_test_customer <<'SQL'
CREATE TABLE customer_invoices (
  doc_ref varchar(128) NOT NULL UNIQUE,
  inv_no varchar(64),
  vendor varchar(200),
  issued_on date,
  grand_total numeric(12, 2)
);
CREATE TABLE customer_lines (
  doc_ref varchar(128) NOT NULL,
  line_ref varchar(64) NOT NULL,
  details text,
  amount numeric(12, 2)
);
SQL
```

Add it as a destination with host `localhost`, database `parsy_test_customer`, and your local Postgres username (leave the password blank if your local server doesn't require one). After a push, inspect the rows directly:

```bash
psql -d parsy_test_customer -c "SELECT * FROM customer_invoices;"
psql -d parsy_test_customer -c "SELECT * FROM customer_lines;"
```

## Engineering workflow

Parsy follows a red-green-refactor loop:

1. Write or update the smallest behavior test that captures the contract.
2. Run the focused test file while iterating.
3. Refactor behind the green test, keeping service objects small and dependencies injected at boundaries.
4. Run the local CI gate before merging.

Service boundaries should stay SOLID-friendly:

- Controllers authenticate, authorize tenant scope, and orchestrate only.
- Intake, extraction, validation, review, export, and security behavior lives in explicit service/value objects.
- External providers sit behind adapter/client interfaces; tests use deterministic fakes at those boundaries.
- Approval-gated actions remain explicit operator decisions, never hidden callbacks.

## Verification commands

Run the complete local CI gate:

```bash
ruby bin/ci
```

Run Rails tests only:

```bash
ruby bin/rails test
```

Run Rails tests with the enforced line-coverage gate:

```bash
COVERAGE=true ruby bin/rails test
```

Run system tests only:

```bash
ruby bin/rails test:system
```

Run the milestone/sample gate used for M1-M4 validation:

```bash
ruby bin/rails test test/models test/services test/controllers test/config test/system
```

CI includes:

- `bin/setup --skip-server`
- RuboCop
- bundler-audit
- importmap audit
- Brakeman with warnings as failures
- Rails tests with `COVERAGE=true` and a 90% minimum line-coverage gate
- Selenium system tests
- seed replant

## Production/deployment notes

Production expects:

- SSL enforced by `config.force_ssl` and `config.assume_ssl`.
- Host allow-list from `APP_HOSTS`.
- Private S3 Active Storage via `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, and `PRIVATE_STORAGE_BUCKET`.
- Separate Kamal `web` and `job` roles; jobs run `bin/jobs`.
- `SOLID_QUEUE_IN_PUMA=false` for the deployment split.
- `RAILS_MASTER_KEY` and database credentials supplied as deployment secrets.

Do not claim launch readiness from CI alone. M5 still needs real closed-pilot operating evidence: supervised batches, correction taxonomy, speed/safety/cost measurements, operator debriefs, and a go/iterate/stop decision.

## Key paths

- `contracts/invoice.schema.json` — Canonical Invoice Schema v2.
- `contracts/region_profile.schema.json` — region/profile contract.
- `contracts/openapi.yaml` — API contract.
- `config/format_registry.yml` — format and route registry.
- `config/validation_rules.yml` — deterministic validation rules.
- `prompts/` — extraction and repair prompts.
- `test/fixtures/files/invoice_parser/samples/` — retained sample corpus required by automated tests.
- `config/blocking_errors.yml` — pilot blocking-error severity and behavior rules consumed by `Canonical::UniversalEngine`.
- `test/services/evaluation/final_docs_samples_test.rb` — final docs sample verification.
