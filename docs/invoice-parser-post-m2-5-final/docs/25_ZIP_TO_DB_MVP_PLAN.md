# M4.5 — Cloud Extraction & Database Delivery MVP Plan

**Status:** Active
**Milestone:** M4.5 (between M4 security/deployment — complete — and M5 closed pilot)
**Supersedes the critical path in:** `21_MVP_REMAINING_WORK.md`
**Related ADRs:** ADR-026 (cloud extraction), ADR-027 (external database delivery); amends ADR-021/ADR-025 (external APIs), extends ADR-019 (exports) and ADR-001 (human-in-the-loop).

---

## 1. Goal

Deliver the end-to-end flow the MVP now targets:

> An operator uploads a compressed ZIP of invoices → background jobs extract each invoice into Canonical Invoice v2 → the operator reviews and **approves** → approved invoices are **pushed into an operator-configured external database** through a schema mapping the operator sets up.

The upload → background-extraction half already exists (`Intake::OperatorUpload` → `Review::ProcessDocumentJob` → `Extraction::DocumentExtractor`). This milestone adds a **working extraction engine** and a **database delivery target**.

## 2. Why this pivot

Two problems block the current design from delivering a usable MVP:

1. **The local model produces 0% schema-valid output.** Per `24_MODEL_SELECTION_REPORT.md` §8, `qwen3-vl:4b` runs and reads images but scores 0/24 schema-valid on the synthetic corpus because the prompt never embeds the nested Canonical Invoice v2 field names — the model guesses `name`/`amount_due`/`ein` instead of `legal_name`/`payable_amount`/`identifiers[]`. It is also slow (40–240 s/invoice) and needs ~16 GB RAM. Nothing ever auto-passes validation, so nothing is deliverable.
2. **There is no database sink.** Delivery today is file-only (JSON/CSV/XLSX via `Canonical::Exports`). The MVP goal is to push structured invoice rows directly into a customer database.

Decision (see ADR-026/ADR-027): adopt a **cloud vision API** as the default extraction provider for the MVP (fastest path to schema-valid output), keep the local model as a selectable fallback, and add an **approval-gated external-database writer** built on the existing canonical relational decomposition (`Canonical::Exports::NormalizedCsv`).

## 3. Architecture seams reused

- **Extraction provider is pluggable.** `Extraction::ProviderAdapter` validates every result against `Canonical::SchemaValidator`; a provider is any object answering `extract_invoice`/`call → {json_text:, metadata:}`. A cloud client drops in beside `LocalExtraction::OllamaClient`.
- **Canonical relational schema already exists.** `Canonical::Exports::NormalizedCsv` decomposes an invoice into `Invoices / Parties / PartyIdentifiers / TaxBreakdowns / LineItems` with defined columns — this is the source schema the DB mapping targets.
- **Approval is the gate.** `Review::ApprovalService` marks a revision approved; the DB push mirrors `Review::ApprovedRevisionExporter` (batch-level action, provenance artifact) but writes rows instead of files.

## 4. Phases, issues, and acceptance criteria

### Phase 1 — Working cloud extraction (fixes the 0% schema-valid blocker)

| Issue | Scope | Acceptance |
| :-- | :-- | :-- |
| M4.5-01 | Embed Canonical v2 schema + one worked example into the extraction prompt (provider-independent) | Schema-valid rate on the 24 scored fixtures rises materially above 0%; field-match accuracy does not regress |
| M4.5-02 | Cloud vision provider client (Gemini) behind the `ProviderAdapter` contract | Client sends page image + parser/OCR text, requests JSON, returns raw text; adapter parses + validates unchanged |
| M4.5-03 | Provider selectable (cloud\|local) via config + API-key secret handling | `PARSY_EXTRACTION_PROVIDER` switches the semantic client; key read from credentials/env, never logged or committed |
| M4.5-04 | Wire cloud provider into spend/quota guard, timeouts, safe-failure mapping | Rate-limit/timeout/HTTP errors map to `SafeFailure`; `Usage::SpendGuard` ceiling pauses calls; no job crash |
| M4.5-05 | Benchmark cloud provider on the 29-fixture corpus | Schema-valid + field-match recorded in `evaluation/`; content-free metadata only |

### Phase 2 — External database destination (config + introspection + mapping)

| Issue | Scope | Acceptance |
| :-- | :-- | :-- |
| M4.5-06 | `Destination::DatabaseConnection` model | Tenant-scoped; adapter allowlist (postgresql/mysql2); credentials encrypted at rest; never logged |
| M4.5-07 | Connection test + schema introspection | Operator can verify connectivity and list target tables + columns (name/type/nullability) via a secondary connection |
| M4.5-08 | `Destination::FieldMapping` | Operator maps canonical relational columns → target tables/columns; mapping validated against the introspected schema |
| M4.5-09 | Destinations UI | Configure connection, run test, browse introspected schema, build and save the mapping |

### Phase 3 — Approval-gated writer

| Issue | Scope | Acceptance |
| :-- | :-- | :-- |
| M4.5-10 | `Destination::InvoiceWriter` | Parameterized, identifier-quoted, idempotent upsert (keyed on `document_id`); re-push does not duplicate |
| M4.5-11 | Hook into approval/export flow | Batch-level "Push to database" action enabled only for approved documents; provenance artifact + audit event recorded |
| M4.5-12 | Push observability & failure handling | Per-row success/failure recorded; partial failures retryable; logging stays content-free |

### Cross-cutting

| Issue | Scope | Acceptance |
| :-- | :-- | :-- |
| M4.5-13 | Security/privacy review (ADR + threat model) | Cloud egress consent/opt-in documented; external-DB credentials threat-modeled (at-rest encryption, SSRF, SQL injection); sign-off recorded |
| M4.5-14 | Docs: ADR-026/ADR-027, PRD/architecture updates | New direction documented; superseded docs marked; issues cite this plan |

M5 gains **M5-08** — pilot validation of the end-to-end DB delivery — and its epic is re-scoped so the pilot exercises upload → cloud extract → review → DB push.

## 5. Security & privacy (the reversal M4 must acknowledge)

M4 was built local-only (content-free logging, private storage, no third-party egress). Cloud extraction sends full invoice images off-box — a deliberate, documented reversal (ADR-026). It must be **opt-in**, disclosed to the tenant, and the API key handled as a secret. External-DB credentials are stored encrypted (ADR-027), writes are parameterized against introspected identifiers, and connection targets are validated. `M4.5-13` is the gate that must close before pilot enablement.

## 6. Explicit deferrals (unchanged from prior plan unless noted)

Still out of scope for M4.5: email ingestion, public signup/billing, multiple regional tax packs, fine-tuning, fully autonomous acceptance (approval gate stays), and native ERP-protocol adapters (the generic DB writer is **not** an ERP integration — it writes rows the operator maps, it does not post accounting entries). Local-model tuning (Ollama keep_alive, flattened grammar, PaddleOCR-VL, NuExtract) moves to `post-mvp` as fallback work.
