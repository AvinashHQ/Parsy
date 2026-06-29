# Remaining Work After Frozen M2

## Corrected critical path

`M2.5 open-source extraction upgrade -> M3 review workflow -> M4 production safety -> M5 closed pilot`

M0-M2 are complete and frozen according to the project owner. M2.5 contains every new open-source integration decision introduced after M2.

## M2.5 — open-source extraction upgrade

Eight issues are defined in `docs/23_M2_5_IMPLEMENTATION_PLAN.md` and `planning/remaining_mvp_issues.csv`:

1. Contract snapshot and feature flags.
2. Digital PDF parser adapter.
3. Scan/layout/OCR adapter.
4. Qwen semantic extraction adapter.
5. Route orchestration and provenance.
6. Synthetic and real-corpus benchmark.
7. Bounded repair and safe failure handling.
8. Model-selection ADR, rollout, and rollback.

**Exit gate:** one selected local route processes supported documents through the frozen M2 interface, records complete provenance and operational metrics, passes functional fixtures, and can be disabled without a schema/domain change.

## M3 — review workflow and acceptance engine

M3 may start fixture-driven UI work in parallel with M2.5, but its end-to-end gate requires M2.5 output.

Work:

- document/batch workflow and jobs;
- risk-ranked review queue;
- source and evidence viewer;
- canonical editor and locale/profile override;
- deterministic acceptance policy;
- immutable revisions and audit events;
- keyboard-first review actions;
- approved-revision-only exports.

**Exit gate:** an operator completes a 50-document batch; unresolved critical/high findings never auto-accept; changed high-risk fields have evidence or explicit confirmation; approved revisions are immutable.

## M4 — security, privacy, reliability, and deployment

Work:

- authentication and tenant isolation;
- private object storage and short-lived access;
- purge, retention, and deletion verification;
- content-free logging proof;
- model/infrastructure quotas and circuit breakers;
- web/job/database deployment and backups;
- restore and failed-job recovery drills;
- privacy, processor, and residency approval;
- dependency, static-security, and upload-abuse CI.

**Exit gate:** tenant isolation, deletion, restore, logging, quota, and security evidence passes.

## M5 — closed live MVP test

Work:

- first supervised 50-document batch;
- correction taxonomy;
- two-week 500-document pilot;
- safety, speed, cost, and precision measurement;
- holdout regression after every relevant change;
- operator debrief and commercial signal;
- go/iterate/stop decision.

**Go gate:** material time savings, at least 99.5% unattended high-risk precision for any auto-accepted cohort, zero escaped critical monetary errors, acceptable unit economics, and at least one request to continue.

## Explicit deferrals

Do not add before M5 evidence:

- direct ERP posting;
- email ingestion;
- public signup and billing;
- multiple regional tax packs;
- fine-tuning;
- broad cloud-provider fallback;
- fully autonomous acceptance;
- mobile application.
