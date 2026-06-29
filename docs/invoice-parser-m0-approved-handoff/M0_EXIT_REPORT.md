# Milestone M0 Exit Report

## Status

| Item | Result |
|---|---|
| Milestone | M0 — Pilot contract and scope freeze |
| Decision | **PASS — start M1** |
| Decision date | 2026-06-29 |
| Evidence status | Assumed/synthetic planning scenario |
| First implementation issue | `M1-01 Implement Canonical Invoice v2` |

## Executive conclusion

The assumed research indicates a repeatable and expensive operator workflow: teams receive heterogeneous supplier invoices, manually normalize the same core fields, perform arithmetic and tax plausibility checks, resolve exceptions, and stage the result in spreadsheets before import.

A reviewed export-only product is useful without direct ERP posting. The strongest first wedge is not universal invoice automation; it is a **high-trust batch review workflow** that reduces operator touch time while preventing unsafe values from silently reaching an export.

The project should proceed to M1 under the frozen constraints in this report.

## M0 evidence summary

| Signal | Assumed result | Gate |
|---|---:|---|
| Qualifying interviews | 7 | ≥5 |
| Organizations represented | 5 | ≥3 recommended |
| Hands-on operators/reviewers | 6 | ≥5 |
| Directly observed workflows | 3 | ≥2 recommended |
| Documents represented in timing samples | 144 | ≥20 |
| Teams finding reviewed CSV/XLSX useful | 6/7 | Positive majority |
| Teams willing to test export-only pilot | 5/7 | ≥2 |
| Selected pilot teams | 2 | 2 |
| Permissioned corpus committed | 240 documents | 150–300 |
| Double-reviewed holdout planned | 100 documents | 100 |

## Baseline workflow

### Selected job to be done

> An English-speaking bookkeeping or AP operator uploads a batch of visual supplier invoices, reviews evidence-backed exceptions, approves normalized accounting data, and exports a workbook or CSV bundle for the team's existing import workflow.

### Measured baseline

| Metric | Assumed result |
|---|---:|
| Median active touch time, mixed workflow | 5.6 min/document |
| Median active touch time, header/totals only | 4.2 min/document |
| Median active touch time, line-item required | 9.1 min/document |
| Mean rework time | 1.4 min/document |
| Documents with at least one exception | 29% |
| Documents requiring external clarification | 8% |
| Active throughput | 10.7 documents/operator-hour |

External waiting time is excluded from the touch-time baseline and reported separately.

## Highest-value pain points

1. Re-keying supplier, invoice, date, currency and total fields.
2. Locating evidence after an extraction or import warning.
3. Reconciling line totals, tax totals and payable amount.
4. Detecting duplicates and credit-note/invoice confusion.
5. Converting reviewed data into a stable import spreadsheet.
6. Correcting low-quality scans and inconsistent supplier identifiers.

## Error distribution

The most frequent categories per 100 sampled documents were:

| Category | Events per 100 documents | Product treatment |
|---|---:|---|
| Source quality/ambiguous text | 14 | Evidence + review |
| Supplier or tax identifiers | 11 | Normalize + validate + review |
| Tax breakdown | 10 | Arithmetic checks; no tax advice |
| Monetary amount | 8 | Blocking reconciliation |
| Date/reference | 7 | Plausibility + review |
| Line-item extraction | 6 | Conditional review-only |
| Duplicate | 5 | Blocking fingerprint warning |
| Document classification | 4 | Block invoice/credit-note ambiguity |
| Currency | 2 | Blocking when absent/ambiguous |

Multiple events may occur on one document.

## M0-01 through M0-07 closeout

### M0-01 — Interview operators and baseline workflow

**PASS.** Seven interviews, five organizations, three direct observations, baseline minutes, workflow stages and error categories recorded.

### M0-02 — Select pilot teams and sign data terms

**PASS in this scenario.** Two pseudonymous pilot profiles accepted supervised, export-only testing and the assumed DPA/permission model.

### M0-03 — Inventory formats, regions, currencies and languages

**PASS.** First-live cohort is English/Latin-script visual documents from multiple countries. Currencies include USD, GBP, EUR, AUD, SGD, INR and AED. Unknown structured inputs are quarantined.

### M0-04 — Freeze required fields and unacceptable errors

**PASS.** `pilot/REQUIRED_FIELDS_V1.yaml` and `pilot/BLOCKING_ERRORS_V1.yaml` are the approved implementation inputs.

### M0-05 — Freeze first-live capability statement

**PASS.** The product claims extraction and arithmetic validation only for the named pilot profile. It does not claim worldwide tax compliance, all-language support or direct posting.

### M0-06 — Collect and double-label initial corpus

**PASS as a plan/commitment.** The assumed commitment is 240 permissioned documents with a 100-document vendor-disjoint holdout. See `pilot/CORPUS_AND_HOLDOUT_PLAN.md`.

### M0-07 — Approve hosting, processor and retention plan

**PASS as an internal decision.** EU-hosted pilot, content-free logs, short retention, explicit purge, no-training provider terms and a processor register are required. Real approvals must replace this assumption before deployment.

## Exit-gate result

The M0 exit gate is satisfied in the assumed scenario:

- two pilot teams find generic reviewed exports useful;
- both accept supervised export-only testing;
- both commit permissioned ground truth;
- field and error boundaries are frozen;
- a corpus and privacy plan exists; and
- no M1 requirement depends on choosing an ERP, country-specific rule pack or AI provider.

## Decision

**Proceed to M1.**

Do not begin M2 model integration or M3 review UI until M1 creates a stable country-neutral contract, arithmetic engine, duplicate logic, export model and versioning policy.
