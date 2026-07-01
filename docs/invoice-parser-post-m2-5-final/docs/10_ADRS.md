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
**Status:** Superseded by ADR-021  
**Decision:** The earlier managed-provider-first decision is no longer active.  
**Reason:** The post-M2 design selected an open-source-first route; ADR-024 assigns its implementation to M2.5 while preserving the completed M2 provider contract.

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


## ADR-021: Open-source-first local extraction
**Status:** Accepted; amended by ADR-026 (cloud extraction is the MVP default; local route becomes a selectable fallback)  
**Decision:** Implement Docling/native parsing, PaddleOCR-VL-1.6, and Qwen3-VL-4B-Instruct as M2.5 candidates behind the provider-neutral contract completed in M2. External APIs remain disabled by default.  
**Reason:** Preserve the completed milestone history while gaining local privacy, model control, and a benchmark path without coupling Rails to one runtime.

## ADR-022: Synthetic fixtures are functional evidence, not accuracy evidence
**Status:** Accepted  
**Decision:** Generated invoices may gate routing, schema, validation, review, and export behavior. Only permissioned, double-reviewed real documents may gate extraction accuracy and production support claims.  
**Reason:** Synthetic layouts underrepresent real-world noise, vendor diversity, and annotation ambiguity.

## ADR-023: M3 cannot call models from web controllers
**Status:** Accepted  
**Decision:** M3 consumes candidate revisions and findings through jobs/services. Controllers never perform inference or mutate candidate revisions. During M2.5, fixture and local providers remain interchangeable behind the same contract.  
**Reason:** Preserve latency isolation, retry control, auditability, rollback, and immutable revision semantics.

## ADR-024: Post-M2 open-source work is M2.5
**Status:** Accepted  
**Decision:** M0-M2 remain frozen. Every new Docling, PaddleOCR-VL, Qwen3-VL, benchmark-selection, quantization, and local-runtime task is tracked in M2.5.  
**Reason:** Milestone history must reflect actual sequencing; completed milestones must not be retroactively expanded.

## ADR-025: M2.5 local model selection, rollout, and rollback
**Status:** Accepted; amended by ADR-026 (external cloud provider re-enabled as MVP default)
**Decision:** Select the M2.5 local open-source route only through the frozen M2 provider adapter: deterministic parser/OCR boundary objects feed a deterministic local semantic client, and Rails stores only Canonical Invoice v2 candidates, bounded findings, and content-free benchmark metadata. The selected configuration for the first local route is the benchmarked Docling/native digital parser where applicable, PaddleOCR-VL layout/OCR for scanned/image inputs, and Qwen3-VL-4B-Instruct through an injected local client fixture or external worker boundary; Rails does not import Python, model weights, CUDA, MLX, Docling, PaddleOCR, Qwen, or OCR runtime dependencies.
**Rejected configs:** Direct model calls from Rails, controller-time inference, external API fallback as an M2.5 dependency, confidence-threshold auto-acceptance, unbounded retries, unsupported structured profiles falling back to vision, and benchmark reports that merge synthetic functional fixtures with permissioned real-corpus accuracy claims.
**Support boundaries:** Synthetic fixtures prove functional routing, schema, validation, evidence plumbing, safe rejection, repair, and rollback only. Permissioned real ground-truth rows are required for field, evidence, hallucination, latency, memory, failure, repair, and quarantine scorecards. Nulls and ambiguity are preserved; deterministic validation remains the acceptance authority.
**Disabled routes:** External APIs, fine-tuning, custom pretraining, unsupported e-invoice profiles, direct ERP posting, and any local runtime that cannot emit version/options/peak-memory metadata are disabled until a separate ADR and benchmark gate approve them.
**Monitoring:** M2.5 reports must record model revision, quantization, runtime, prompt hash, parser/OCR versions, device profile, p95 latency, peak memory, OOM rate, repair rate, quarantine rate, evidence coverage, hallucinated non-null field rate, and safe-failure counts without raw source text, evidence snippets, party names, or invoice numbers.
**Rollback rules:** A feature-flag disablement must restore the existing provider without schema migration or Canonical Invoice v2 changes. Rollback verification is recorded in the benchmark/ADR evidence before pilot enablement, and any local route that violates the provider contract, content-free logging rule, memory limit, or safe-failure path is disabled rather than patched around in controllers.

## ADR-026: Cloud vision extraction is the MVP default
**Status:** Accepted (amends ADR-021 and ADR-025)
**Decision:** The default extraction provider for the MVP is a managed cloud vision LLM (Google Gemini) driven through the frozen M2 provider contract. The local open-source route (Qwen3-VL-4B + GLM-OCR) remains selectable as a fallback via `PARSY_EXTRACTION_PROVIDER`. The extraction prompt embeds the Canonical Invoice v2 field schema and one worked example regardless of provider.
**Reason:** The local route scores 0% schema-valid on the synthetic corpus and needs ~16 GB RAM and 40–240 s/invoice (`24_MODEL_SELECTION_REPORT.md` §8). A cloud vision model with structured JSON output is the fastest path to schema-valid, deliverable output for the MVP.
**Reversal:** ADR-021 and ADR-025 disabled external APIs by default; this ADR re-enables a managed provider as the MVP default. Cloud egress is opt-in, tenant-disclosed, and the API key is a managed secret (not committed, not logged).
**Boundaries preserved:** Controllers never call models (ADR-023) — inference stays in jobs/services behind the provider contract. Deterministic schema validation remains the acceptance authority (ADR-010). Content-free logging (M4-04) applies to all provider metadata.

## ADR-027: External database as an approved-invoice delivery target
**Status:** Accepted (extends ADR-019; gated by ADR-001)
**Decision:** In addition to canonical JSON/CSV/XLSX file exports, the MVP can push **approved** invoices into an operator-configured external database. The operator configures a connection (encrypted credentials, adapter allowlist), Parsy introspects the target schema, and the operator maps the canonical relational tables (Invoices / Parties / PartyIdentifiers / TaxBreakdowns / LineItems) to target tables and columns. Writes are approval-gated, parameterized, identifier-quoted, and idempotent (keyed on `document_id`).
**Reason:** Direct database delivery is the MVP goal, and the canonical relational decomposition already exists (`Canonical::Exports::NormalizedCsv`), so the writer reuses it.
**Boundaries:** This is a generic row writer, not an ERP-protocol integration (ADR-019's ERP adapters stay deferred) and not automated accounting posting — ADR-001's human-in-the-loop gate is preserved: nothing is written until an operator approves. Credentials are encrypted at rest; connection targets are validated; SQL injection is prevented via parameterization and quoted identifiers.
