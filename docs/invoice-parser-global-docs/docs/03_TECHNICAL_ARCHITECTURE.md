# Technical Architecture — Global Rails Modular Monolith

## Decision

Use a Rails 8.1 modular monolith with one repository and one container image running two roles:

- **web:** Puma/Thruster, ERB/Hotwire, authenticated downloads, JSON endpoints.
- **job:** Solid Queue for intake inspection, extraction, validation, export, and retention.

Core stack:

- Ruby 3.4.x and Rails 8.1.x, pinned in the implementation repository.
- PostgreSQL for workflow state, JSONB canonical revisions, audit metadata, and Solid Queue.
- Active Storage with private S3-compatible object storage.
- Active Job + Solid Queue; no Redis required for MVP.
- Hotwire for the review interface.
- Managed multimodal document provider behind an adapter.
- Deterministic structured parsers and versioned region packs.

## Architecture principle

The system has two axes that must remain independent:

1. **Source syntax:** PDF/image, UBL, CII, Factur-X, or another structured format.
2. **Jurisdiction semantics:** generic, India GST, EU VAT, US sales tax, or another region pack.

A UBL invoice is not automatically an EU invoice, and a PDF from India is not automatically safe to validate with India GST rules. Format and jurisdiction are detected, recorded, and confirmed separately.

## Production components

| Component | Responsibility |
|---|---|
| Rails web | Authentication, upload session, review, approval, export, deletion |
| Rails job | Inspection, format routing, provider calls, validation, export, purge |
| PostgreSQL | Tenants, batches, documents, immutable revisions, findings, attempts, profiles |
| Active Storage | Temporary source files, thumbnails, generated exports |
| Private object store | Encrypted blobs and lifecycle safety net |
| Format detector | MIME/magic-byte, namespace, embedded-file, and profile detection |
| Structured adapters | Deterministic UBL/CII-family mapping into Canonical Invoice v2 |
| Visual extraction provider | Schema-constrained extraction for PDF/image route |
| Validation engine | Universal rules plus optional regional pack |
| Capability registry | Format/language/region release state and benchmark version |
| Export adapters | Generic exports first; ERP/region adapters later |

## Processing routes

### Route A — structured invoice

1. Inspect file safely.
2. Identify namespace/root/profile/version or an embedded structured payload.
3. Run available official XSD/Schematron/business-rule validation.
4. Map source fields deterministically into Canonical Invoice v2.
5. If a visual representation exists, extract only the minimum evidence required for conflict checks.
6. Run universal validation.
7. Resolve and run a benchmarked region pack, or `global_generic_v1`.
8. Store immutable candidate revision and findings.

### Route B — visual invoice

1. Inspect file, page count, orientation, resolution, and encryption.
2. Send the allowed pages to the selected managed provider using a versioned schema/prompt.
3. Reject schema-invalid output.
4. Run one targeted repair only for explicitly repairable fields.
5. Run universal validation.
6. Resolve and optionally run a benchmarked region pack.
7. Store immutable candidate revision and findings.

### Route C — unsupported or unsafe

Quarantine with a machine-readable reason. Do not silently fall back from an unrecognized XML/JSON format to the visual model and do not route documents to an unapproved provider.

## Rails domain model

### Tenant

Configuration boundary for data access, retention, allowed processors, hosting region, enabled profiles, and export mappings.

### Batch

Upload group and aggregate progress. A batch is not the transaction boundary for processing; each document progresses independently.

### Document

Stable identity for the received business document. Stores source metadata, hash, detected format, processing state, and current approved revision reference.

### DocumentRevision

Immutable canonical JSONB candidate or operator-approved revision. Contains schema version, source parser/model provenance, language/country/currency signals, and applied rule-pack version.

### ProcessingAttempt

One external model or deterministic parser execution with status, latency, route, token/cost metadata, error code, and version hashes. It does not store raw response bodies after canonicalization.

### ValidationFinding

Deterministic finding with code, severity, field paths, pack, pack version, observed/calculated values where non-sensitive, and resolution state.

### ReviewEvent

Actor, action, changed field paths, reason, revision IDs, and timestamp. Do not duplicate full invoice content.

### ExportArtifact

Export type, mapping version, approved revision set, storage blob, status, and deletion deadline.

### CapabilityProfile

The release state of a named combination such as `visual/en/global_generic_v1` or `ubl/peppol_billing_3/eu_vat_core_v1`, linked to its benchmark report.

## State model

```text
uploaded
  → inspecting
  → routed_structured | routed_visual
  → extracting
  → validating
  → needs_review | ready_for_approval | failed | quarantined
  → approved
  → exported
  → purged
```

A new extraction or operator edit creates a new revision. Approved revisions are immutable.

## Job topology

- `inspect`: file safety and route selection.
- `extract_visual`: managed model calls; low initial concurrency.
- `parse_structured`: deterministic XML/hybrid parsing.
- `repair`: one targeted model repair; separate cost-limited queue.
- `validate`: universal and region-pack validation.
- `export`: JSON/CSV/XLSX generation.
- `maintenance`: retention, orphan reconciliation, registry refresh checks.

Suggested pilot concurrency:

- inspect: 2–4 threads
- extract_visual: 2 threads
- parse_structured: 2 threads
- repair: 1 thread
- validate/export: 2 threads
- maintenance: 1 thread

Provider rate limits and memory measurements override these defaults.

## Domain idempotency

Use an application idempotency key, not queue uniqueness alone:

```text
source_sha256
+ canonical_schema_version
+ route_profile_version
+ provider_or_parser_version
+ prompt_hash
+ region_pack_version
```

An identical key may reuse a completed candidate if tenant policy allows. It must never overwrite an approved revision.

## Canonical persistence

Store evolving canonical data in JSONB and duplicate a small set of searchable normalized columns:

- tenant and batch
- source hash
- supplier primary identifier key
- normalized supplier name key
- document number key
- issue date
- currency code
- payable amount as `numeric(24,8)`
- buyer primary identifier key
- source format family/profile
- document language/country candidates
- status and review status

Do not create country-specific columns such as `gstin`, `cgst`, or `irn` in the core table.

## Format detection

`FormatDetector` must return:

```ruby
FormatDetection.new(
  family: :visual_pdf,
  profile: nil,
  version: nil,
  confidence: :deterministic,
  embedded_payloads: [],
  warnings: []
)
```

Detection uses magic bytes, MIME sniffing, PDF catalogue/attachments, XML namespaces/root elements, and known profile identifiers. Filename extension is only a hint.

## Region-pack boundary

```ruby
module RegionPacks
  class Base
    def metadata = raise NotImplementedError
    def normalize(canonical:) = canonical
    def validate(canonical:, context:) = []
    def duplicate_key_parts(canonical:) = []
  end
end
```

A pack cannot call a model, mutate approved data, make network tax determinations, or post to an ERP. External identifier checks, if ever added, are separately permissioned and failure-tolerant.

## Acceptance engine

Auto-accept is decided by:

- schema validity;
- no unresolved critical/high finding;
- required evidence present;
- known source route;
- benchmarked capability profile;
- profile precision at or above configured gate;
- no operator/tenant rule requiring review.

Model-provided confidence is metadata only.

## Storage and privacy

- Private buckets only.
- Short-lived authenticated access.
- Jobs receive record IDs, never raw blobs or invoice text.
- Blob lifecycle rules are a safety net, not proof of deletion.
- Tenant hosting region and processor policy are explicit configuration.
- Source, derived thumbnails, and export retention are independent.
- Structured payloads are treated as source content and purged with the original.

## Observability

Allowed dimensions:

- tenant pseudonymous ID
- document/batch internal IDs
- route and format profile
- language/country/currency codes
- rule-pack ID/version
- status/finding codes
- latency, pages, token counts, and cost
- queue depth and retry counts

Forbidden:

- source text or images
- party names/addresses
- full identifiers or account numbers
- invoice numbers
- evidence snippets
- canonical/model response bodies

## Deployment profiles

### Supervised pilot

- One 2–4 GB VPS for web/job.
- PostgreSQL on the VPS only if the service can tolerate restore-based recovery.
- Private external object storage.
- Encrypted off-host database backups and tested restore.
- One hosting region approved by the pilot customers.

### Operational production

- Independently scalable web/job roles.
- Managed PostgreSQL with point-in-time recovery.
- Multi-zone object storage with access logs/lifecycle.
- Centralized secrets, alerting, backup verification, and incident process.
- Separate regional deployments only when customer/legal requirements justify the cost.

## Reliability rules

- One document failure never fails the batch.
- External calls occur outside database transactions.
- State transitions use locks and short transactions.
- Retries are code-specific with bounded exponential backoff.
- Schema errors are not blindly retried.
- Provider outage leaves documents queued/paused rather than silently changing processors.
- Region-pack and format-registry changes are feature-flagged and reversible.

## Scale path

1. Increase queue workers conservatively.
2. Move PostgreSQL to managed service.
3. Separate web/job VMs.
4. Add read replicas only for measured query pressure.
5. Add a specialized parser only when benchmark/cost data proves value.
6. Split a service only when process isolation or a non-Ruby runtime creates a measured advantage.
