# Corpus and Holdout Plan

**Corpus version:** `pilot_corpus_v1`  
**Evidence status:** assumed commitment; real permission records required before ingestion.

## Target corpus

| Split | Documents | Purpose | Visibility |
|---|---:|---|---|
| Development | 100 | Schema mapping, prompt iteration, validator fixtures | Engineering/data team |
| Validation | 40 | Threshold and repair decisions | Restricted |
| Frozen holdout | 100 | Unseen release scoring | Restricted; no prompt tuning |
| **Total** | **240** |  |  |

All 240 documents receive double-reviewed header/total ground truth. At least 120 receive full line-item ground truth.

## Representation targets

- Pilot Alpha: 120 documents
- Pilot Beta: 120 documents
- digital PDF: approximately 55%
- scans: approximately 30%
- phone/image captures: approximately 15%
- invoices: approximately 79%
- credit notes: approximately 13%
- receipts/debit notes: approximately 8%

## Holdout controls

- 100 documents frozen before model/prompt tuning;
- at least 60% vendor-disjoint from development;
- hashes and split assignment immutable;
- corrections require two reviewers or an adjudicator;
- no holdout pages in screenshots, demos or prompt examples;
- all benchmark reports pin schema, prompt, model, format profile and validation-rule versions.

## Permission records

Each source document must reference:

- organization permission ID;
- allowed purpose;
- allowed processors;
- permitted storage region;
- retention deadline;
- whether derived labels may be retained; and
- whether the document may be reused after the pilot.

## M1 dependency

M1 uses synthetic fixtures and field decisions. It does not need source files. The real corpus becomes a hard dependency for M2-07, the benchmark runner.
