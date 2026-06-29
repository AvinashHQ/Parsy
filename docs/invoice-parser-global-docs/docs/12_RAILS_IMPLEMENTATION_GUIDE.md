# Rails Implementation Guide

## Generate a clean application

Pin exact Ruby/Rails versions in the implementation repository, then generate a conventional app:

```bash
gem install rails -v 8.1.3
rails _8.1.3_ new invoice_parser \
  --database=postgresql \
  --javascript=importmap \
  --css=tailwind
cd invoice_parser
bin/rails active_storage:install
bin/rails solid_queue:install
bin/rails db:prepare
```

Treat this documentation pack as the source of truth; do not copy a stale generated scaffold.

## Implementation order

Follow milestones M0–M5. Within code, implement in this order:

1. Decimal value objects and Canonical Invoice v2 validation.
2. Immutable document revision model.
3. Universal validation engine.
4. Generic exporters.
5. Secure upload and format detector.
6. Visual provider adapter and benchmark runner.
7. Workflow states/jobs.
8. Hotwire review.
9. Retention/security/deployment.
10. Only then add a regional pack or structured adapter demanded by pilot data.

## Suggested domain objects

- `Tenant`
- `User`
- `Batch`
- `Document`
- `DocumentRevision`
- `ProcessingAttempt`
- `ValidationFinding`
- `ReviewEvent`
- `ExportArtifact`
- `CapabilityProfile`

Avoid projecting every canonical field into Active Record columns. Keep canonical data in versioned JSONB and denormalize only search/duplicate/list-view keys.

## Value objects

### DecimalValue

- Parse canonical decimal strings with `BigDecimal`.
- Reject exponent notation unless explicitly allowed.
- Preserve canonical string serialization.
- Apply currency minor-unit/tolerance rules outside the value object.

### CountryCode, CurrencyCode, LanguageTag

- Validate syntax locally.
- Use versioned registries for current code membership.
- Do not make outbound network calls during document validation.

### EvidenceLocator

Represents visual page/snippet/bounding box or structured source path.

## Service boundaries

- `Intake::FileInspector`
- `Intake::FormatDetector`
- `Structured::Router`
- `Structured::UblAdapter`
- `Structured::CiiAdapter`
- `Extraction::Provider`
- `Extraction::Pipeline`
- `Canonical::SchemaValidator`
- `Validation::UniversalEngine`
- `RegionPacks::Registry`
- `Acceptance::Policy`
- `Exports::CanonicalJson`
- `Exports::NormalizedCsv`
- `Exports::Workbook`
- `Retention::PurgeBatch`

Use a service object when work spans external I/O, multiple records, a transaction boundary, or a versioned strategy. Simple CRUD remains conventional Rails.

## Jobs

- `InspectDocumentJob`
- `ExtractVisualDocumentJob`
- `ParseStructuredDocumentJob`
- `RepairExtractionJob`
- `ValidateRevisionJob`
- `GenerateBatchExportJob`
- `PurgeExpiredDataJob`
- `ReconcileOrphanedBlobsJob`

External calls occur outside transactions. Commit state before enqueue using `after_commit`-safe patterns.

## Region packs

Recommended layout:

```text
app/domain/region_packs/
  base.rb
  registry.rb
  global_generic/v1.rb
  india_gst/v1.rb          # feature flagged, not launch dependency
```

A pack returns findings and optional normalized extensions; it does not call models/providers or write records.

## Structured formats

- Use `Nokogiri` with external entities and network access disabled.
- Consider `HexaPDF` only when M2 proves embedded-file inspection is required; keep PDF parsing bounded.
- Official XSD/Schematron artefacts are stored or fetched through a checksum-pinned build process, subject to their terms.
- Unknown profiles are quarantined.
- Deterministic adapter tests use small redacted/synthetic fixtures.

## Recommended dependency policy

Start small:

- `json_schemer` — Canonical Invoice contract validation.
- `caxlsx` — XLSX export.
- `aws-sdk-s3` — production Active Storage service.
- `nokogiri` — safe XML inspection/parsing (already common in Rails stack).
- a maintained ISO currency/country registry library only if its update/versioning behavior is acceptable; otherwise vendor a small versioned data file.

Add PDF/virus/structured-validation dependencies only in the milestone that needs them. Avoid Devise, Pundit, AASM, Sidekiq, React, and dependency-injection frameworks until complexity justifies them.

## Hotwire review

- Turbo Stream batch progress.
- Turbo Frame for active document.
- Server-rendered findings grouped by severity.
- Stimulus for keyboard shortcuts, split-pane sizing, and evidence focus.
- Form submissions create a revision; they do not mutate approved JSON in place.
- Locale display formatting is separate from stored normalized values.
- Add RTL layout tests before enabling RTL language profiles.

## Exports

- Escape spreadsheet formula prefixes from untrusted strings.
- Write monetary decimal strings without float conversion.
- Include currency on every exported monetary grouping.
- Use separate sheets/tables for parties, identifiers, taxes, and lines.
- Build exports from approved revision IDs captured when the export job starts.
- Store checksum and row counts.

## Testing layers

- Pure Ruby unit tests for decimal arithmetic, normalization, validators, packs.
- Contract tests for JSON Schema and provider output.
- Parser fixtures for format detection/structured adapters.
- Model tests for revision immutability, tenant scoping, state transitions.
- Job tests for retries/idempotency.
- Request tests for uploads and cross-tenant access.
- System tests for review speed/keyboard flow.
- Golden-set benchmark task separate from Rails test suite.
- Logging tests with seeded canary identifiers/text.

## Security defaults

- Force SSL and secure cookies.
- Validate file content and bound parsing resources.
- Disable XML external entities/network access.
- Redact parameters and never log canonical payloads.
- Use Brakeman and dependency audit in CI.
- Add authorization tests before broad pilot access.
- Store secrets outside source control.

## Performance defaults

- One Puma process with 2–5 threads on a small pilot VPS.
- One Solid Queue process with route-specific worker pools.
- Direct-to-object-store upload when app memory or request duration requires it.
- Stream blob downloads.
- Generate exports asynchronously.
- Index list/duplicate lookups before adding cache infrastructure.
