---
name: contract-validate
description: Verify external contracts -- API specs, database schemas, protobuf definitions, device/protocol descriptors
metadata:
  audience: engineers
  scope: iterative-validation
---
# Contract Validate

## When to use
Triggered automatically by `smart-validate` when external contract files change, or manually. Contracts are anything a party outside this codebase depends on: API request/response shapes, database schemas and migrations, protobuf/JSON schemas, serialized persistence models, and device/protocol descriptors (see the "Repo contracts" overlay section when present, stamped from `templates/skill-overlays/contract-validate/<slug>.md`).

## Issue-filing contract checklist (for `issue-evidence-gate` / routines)
When an issue asserts a contract capability, spec code, or "no contract change needed", BEFORE filing it the routine (or the `issue-evidence-gate`) MUST:
1. **Read the current contract source** — the descriptor/schema/spec file in this repo — and confirm what is actually declared.
2. **Confirm and CITE any external spec value** (usage codes, status codes, field semantics) against the authoritative spec. An unconfirmed value is an Unverified assumption, never a Verified fact. Do not guess byte sequences or spec codes.
3. **Consult the repo's authoritative contract doc** (the overlay names it) — including its compatibility rules.
4. **Assess breaking impact:** anything outside the currently declared contract ⇒ a contract change ⇒ Feasibility verdict `needs-architecture-change` (+ the migration/compatibility cost), NOT "no change needed".

Map results to the gate's verdicts: contract check `pass` → `VERIFIED`; `warn`/unsure → `UNVERIFIED` (flag for manual review); `fail` (incl. a backward-compat break) → `REFUTED`.

## Trigger patterns (generic — the repo overlay refines them)
```
data models / entities / DTOs
descriptor / schema / proto / migration files
API interface definitions, request/response models
dependency manifest changes affecting serialization
```

## Workflow

### Step 1: Identify contract changes
1. Get changed files and classify which represent contracts:
   - **Protocol/device descriptors**: descriptor byte arrays, usage tables, report structures (where the repo has them).
   - **Data models**: classes used for persistence or serialization.
   - **Proto/schema files**: protocol buffers, JSON schemas, DB migrations, or similar.
   - **API contracts**: client interface definitions, request/response models.

### Step 2: Protocol/descriptor validation (repos with a device/protocol surface)
2. If protocol/descriptor code changed:
   - Verify descriptor structures are valid (correct lengths, proper spec IDs).
   - Check that identifier assignments (report IDs, field tags) are unique and consistent.
   - Verify concrete message/report structures match the declared descriptor/schema.
   - Check backward compatibility -- existing peers/hosts/clients should still work.
   - Cross-reference the repo's authoritative contract doc (see overlay).

### Step 3: Data model compatibility
3. If data models changed:
   - Check for breaking changes in persisted models.
   - Verify a migration path exists for schema changes.
   - Check that default values are provided for new fields.
   - Verify serialization annotations are correct.

### Step 4: Backward compatibility
4. Assess backward compatibility of contract changes:
   - Can existing data be read after the change?
   - Can existing peers/clients still communicate after the change?
   - Are new required fields populated by existing code paths?

### Step 5: Focused tests
5. Run focused tests for changed contract code (smart-validate routing / projects.yaml `commands:`), including any contract-specific suites the overlay names.

## Output format
```
## Contract Validation Results
### Changed contract files
- [file list with classification]

### Protocol/descriptor contracts
| Check | Status | Details |
|-------|--------|---------|
| Descriptor validity | pass/warn/fail | ... |
| Identifier uniqueness | pass/fail | ... |
| Peer compatibility | pass/warn/fail | ... |

### Data model compatibility
| Check | Status | Details |
|-------|--------|---------|
| Breaking changes | pass/warn/fail | ... |
| Migration path | pass/warn/fail | ... |
| Default values | pass/warn | ... |
| Serialization | pass/warn | ... |

### Backward compatibility
| Check | Status | Details |
|-------|--------|---------|
| Data readability | pass/warn/fail | ... |
| Peer/client compatibility | pass/warn/fail | ... |
| Required field population | pass/warn | ... |

### Focused tests
- Status: PASS / FAIL / SKIPPED

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2, failures are reported and accumulated but do not block commits. They become blocking at Phase 3.

**Exception**: Breaking contract changes that would disconnect existing peers/clients or corrupt persisted data are immediate blockers.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Contract correctness is critical for compatibility -- treat errors as `fail`.
- Do not guess byte sequences or spec codes. If unsure, flag for manual review.
- Check the repo's authoritative contract doc (overlay) for reference data.
- Data model breaking changes without migration are `fail`.
- Do not flag changes in test fixtures or mock data.
