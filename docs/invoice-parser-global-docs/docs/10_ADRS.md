# Architecture Decision Records

## ADR-001: Human-in-the-loop before posting
**Status:** Accepted  
**Decision:** MVP exports approved drafts/data only; it never posts accounting entries automatically.  
**Reason:** Silent invoice errors have disproportionate financial and trust impact.

## ADR-002: Canonical schema before source and ERP adapters
**Status:** Accepted  
**Decision:** Every visual model, structured format, region pack, and export adapter maps through Canonical Invoice v2.  
**Reason:** Prevents provider, country, and ERP vocabularies from contaminating core logic.

## ADR-003: Managed multimodal provider, no self-hosted GPU
**Status:** Accepted  
**Decision:** Use a paid managed provider for the visual path; benchmark alternatives behind the same adapter.  
**Reason:** Lowest operational burden and fastest pilot iteration.

## ADR-004: Rails modular monolith
**Status:** Accepted  
**Decision:** Ruby/Rails, PostgreSQL, Active Storage, Solid Queue, and Hotwire.  
**Reason:** The product is a CRUD/review workflow with bounded asynchronous processing; Rails minimizes integration surface for one developer.

## ADR-005: PostgreSQL as workflow system of record
**Status:** Accepted  
**Decision:** Store workflow metadata, immutable canonical revisions, findings, audit, and queue tables in PostgreSQL.  
**Reason:** Transactions, locking, JSONB, indexing, and simpler operations.

## ADR-006: Solid Queue before Redis/Sidekiq
**Status:** Accepted  
**Decision:** Use Active Job with Solid Queue for MVP.  
**Reason:** Durable background processing without another stateful system.

## ADR-007: Active Storage for temporary files
**Status:** Accepted  
**Decision:** Private object storage in production; disk only locally.  
**Reason:** Standard Rails attachment lifecycle and authenticated delivery.

## ADR-008: VPS pilot, managed database when dependency rises
**Status:** Accepted  
**Decision:** One small VPS may run web/job for a supervised pilot; production dependency triggers managed PostgreSQL and stronger recovery.  
**Reason:** Low fixed cost with a documented reliability upgrade path.

## ADR-009: Explicit retention, not blanket zero-retention claim
**Status:** Accepted  
**Decision:** Publish and implement concrete deletion windows until every processor contract/configuration proves otherwise.  
**Reason:** Application deletion alone does not determine provider retention.

## ADR-010: Deterministic acceptance, not model confidence
**Status:** Accepted  
**Decision:** Auto-accept uses schema, evidence, findings, and measured profile precision.  
**Reason:** Model confidence is not calibrated accounting correctness.

## ADR-011: Hotwire, not a SPA
**Status:** Accepted  
**Decision:** ERB/Turbo/Stimulus for the initial review workflow.  
**Reason:** Lower code volume and no duplicated frontend domain model.

## ADR-012: Global canonical core, not country-union schema
**Status:** Accepted  
**Decision:** Identifiers, tax breakdowns, classifications, references, and extensions are typed arrays; no country-specific top-level fields.  
**Reason:** New regions should not require destructive core schema changes.

## ADR-013: Decimal strings in JSON
**Status:** Accepted  
**Decision:** Canonical money/rates use decimal strings and Ruby `BigDecimal`; PostgreSQL uses `numeric`.  
**Reason:** Avoid binary floating errors and two-decimal assumptions across currencies and unit prices.

## ADR-014: Structured data before vision extraction
**Status:** Accepted  
**Decision:** Detect and deterministically parse recognized structured or embedded invoice payloads before using a multimodal model.  
**Reason:** Lower cost, higher reproducibility, and better conformance diagnostics.

## ADR-015: Format and jurisdiction are separate
**Status:** Accepted  
**Decision:** Source-format adapter and region-rule pack are independently selected and versioned.  
**Reason:** The same syntax can be used across jurisdictions, and the same jurisdiction can receive multiple syntaxes.

## ADR-016: Versioned regional packs
**Status:** Accepted  
**Decision:** Country/tax semantics live in deterministic versioned packs with independent benchmarks and feature flags.  
**Reason:** Regional rules change and must be reversible without rewriting core extraction.

## ADR-017: Capability levels replace universal support claims
**Status:** Accepted  
**Decision:** Publish ingest, extraction, arithmetic, region, export, and conformance capabilities separately.  
**Reason:** “Supports a country” is ambiguous and unverifiable.

## ADR-018: English generic profile is the first live dependency
**Status:** Accepted  
**Decision:** First live MVP is benchmarked on English visual invoices across multiple countries/currencies; non-English and regional packs remain review-only or disabled.  
**Reason:** Reduces dataset and UI complexity while preserving global architecture.

## ADR-019: Generic exports before ERP integrations
**Status:** Accepted  
**Decision:** Canonical JSON and normalized CSV/XLSX are launch requirements; Tally, QuickBooks, Xero, SAP, and other adapters are post-evidence modules.  
**Reason:** Direct integrations add authentication, mapping, versioning, and liability before the core workflow is validated.

## ADR-020: Regional legal validity is not an MVP feature
**Status:** Accepted  
**Decision:** The product may read structured e-invoices but does not initially certify, generate, sign, transmit, or archive them as legally compliant documents.  
**Reason:** Those capabilities require official validators, changing mandates, network access, signatures, and legal/operational obligations.
