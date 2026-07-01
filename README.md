# Parsy — AI Invoice Parser

Rails 8.1 modular monolith for a supervised, invite-only invoice intake and exception-review MVP.

Parsy normalizes invoices into Canonical Invoice Schema v2, routes visual/structured inputs safely, keeps evidence attached to review decisions, exports only approved revisions, and enforces tenant-scoped security controls before live pilot use.

## Current milestone status

The active implementation source is `docs/invoice-parser-post-m2-5-final/`.

| Milestone | Status | Current evidence |
| --- | --- | --- |
| M0 — Pilot contract and scope freeze | Complete, owner-declared | `docs/invoice-parser-post-m2-5-final/planning/milestone_status.csv`; GitHub milestone has no open issues |
| M1 — Canonical contract and deterministic core | Complete | Canonical schema/domain/currency/validator/export tests |
| M2 — Safe intake and reproducible extraction | Complete | Upload inspection, routing, provider contract, repair, provenance, and structured-adapter tests |
| M2.5 — Open-source extraction upgrade | Complete | Local parser/semantic route/benchmark tests over the final synthetic corpus manifest |
| M3 — Human review and safe acceptance | Complete | Review workflow, 50-document keyboard system flow, immutable approval, and approved-only export tests |
| M4 — Security, privacy, reliability, deployment | Complete | Tenant isolation, private storage, purge, content-free logging, quota, restore, privacy, production config, upload-abuse, Brakeman, and dependency-audit gates |
| M4.5 — Cloud extraction and database delivery | Planned | MVP pivot: cloud vision extraction (fixes the 0% schema-valid local model) + push approved invoices into an operator-configured external database. See `docs/invoice-parser-post-m2-5-final/docs/25_ZIP_TO_DB_MVP_PLAN.md` and GitHub milestone M4.5 |
| M5 — Closed live MVP test | Planned | Pilots the M4.5 flow; requires M4.5 delivery, then real supervised pilot operating evidence |
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

## Final docs sample coverage

The final docs sample package lives at:

```text
docs/invoice-parser-post-m2-5-final/samples/
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
timeout 120 rbenv exec ruby bin/rails test test/services/evaluation/final_docs_samples_test.rb
```

Run the focused intake regression gate:

```bash
timeout 120 rbenv exec ruby bin/rails test test/services/intake/upload_inspector_test.rb
```

## Prerequisites

- Ruby 3.4.8 via rbenv.
- PostgreSQL available locally.
- Bundler.
- Chrome/Chromium for Selenium system tests.
- AWS S3 credentials only when exercising production/private object storage outside local disk-backed development/test.

## Local setup

```bash
rbenv local 3.4.8
bundle install
cp .env.example .env
bin/rails db:prepare
```

If `bin/rails` resolves to the macOS system Ruby, run Rails commands through rbenv explicitly:

```bash
RBENV_VERSION=3.4.8 rbenv exec ruby bin/rails zeitwerk:check
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
rbenv exec ruby bin/rails console
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
- `/review/batches` — tenant-scoped batch list.
- `/review/batches/:id` — batch progress and risk queue.
- `/review/documents/:id` — evidence-backed document review/editor.
- `/up` — health check.

Current UI scope: review and export workflows. There is no public upload form route yet; intake/extraction are service-layer/test-harness workflows at this milestone.

## Verification commands

Run the complete local CI gate:

```bash
timeout 180 rbenv exec ruby bin/ci
```

Run Rails tests only:

```bash
timeout 180 rbenv exec ruby bin/rails test
```

Run system tests only:

```bash
timeout 120 rbenv exec ruby bin/rails test:system
```

Run the milestone/sample gate used for M1-M4 validation:

```bash
timeout 180 rbenv exec ruby bin/rails test test/models test/services test/controllers test/config test/system
```

CI includes:

- `bin/setup --skip-server`
- RuboCop
- bundler-audit
- importmap audit
- Brakeman with warnings as failures
- Rails tests
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
- `docs/invoice-parser-post-m2-5-final/` — current product, architecture, planning, sample, and evidence pack.
- `test/services/evaluation/final_docs_samples_test.rb` — final docs sample verification.
