# Operations Runbook

## Service objectives for supervised MVP

- Batch and review UI availability target: 99% during agreed pilot hours.
- No silent loss of an uploaded document.
- No cross-tenant access.
- Zero escaped critical monetary mismatch from auto-accepted output.
- Raw-document deletion completed within configured deadline, with verifier alerts on failure.

These are internal pilot objectives, not contractual SLAs.

## Routine checks

Daily during pilot:

- failed/quarantined documents by code;
- queue age and depth by route;
- provider latency/error and spend;
- repair rate;
- deletion verifier and orphan count;
- storage growth;
- backup completion;
- capability/profile distribution;
- critical/high unresolved findings;
- export failures.

Weekly:

- restore sample backup;
- review dependency/security alerts;
- inspect cost per successful document;
- audit rule-pack and format-registry changes;
- review correction taxonomy and profile drift.

## Failed visual extraction

1. Check error class: transient, rate limit, invalid request, schema invalid, unsupported, or cost ceiling.
2. Retry only transient/rate-limit errors with bounded backoff.
3. Do not retry schema-invalid output more than the configured targeted repair.
4. If provider incident persists, pause extraction. Do not change processor/region without tenant approval.
5. Preserve source until the normal retention deadline or operator deletion.
6. Surface actionable state in UI.

## Failed structured parsing

1. Confirm detected namespace/profile/version.
2. Capture content-free parser error code and source path.
3. Quarantine unknown versions rather than guessing a nearby profile.
4. If safe visual representation exists, operator may explicitly choose visual extraction under a separate attempt.
5. Add a fixture before enabling a parser fix.

## Queue backlog

- Alert on oldest-job age, not only count.
- Pause new intake if spend/provider limits or disk/database pressure make processing unsafe.
- Scale job role before changing queue technology.
- Verify no job holds a database transaction during external calls.
- Requeue by internal document ID only.

## Cost ceiling reached

1. Stop new external model calls.
2. Continue deterministic structured parsing, validation, review, export, and deletion.
3. Show `COST_LIMIT_PAUSED`.
4. Review token/page spikes and repair loops.
5. Resume only after administrator action or scheduled reset.

## Region-pack problem

Symptoms: sudden increase in findings, identifier false positives, or tax mismatches after a pack update.

1. Disable the affected pack/version through feature flag.
2. Fall back to `global_generic_v1` with explicit `REGION_RULES_NOT_APPLIED` notice.
3. Do not alter previously approved revisions.
4. Re-run validation/holdout fixtures.
5. Publish a new pack version; never mutate historical semantics in place.

## Currency registry change

- Pin registry version/date in deployments.
- Test changed currency/minor-unit entries.
- Reprocessing is opt-in because historical documents use currency rules effective at their issue date where relevant.
- Never update payable values automatically because a code list changed.

## Deletion failure

1. Mark batch/document `purge_failed` and prevent normal access where possible.
2. Retry database records, attachments, derivatives, exports, and multipart uploads independently.
3. Query object storage by internal prefix and expected blob IDs.
4. Alert the privacy/incident owner when deadline risk exists.
5. Record content-free purge evidence and final completion time.

## Suspected data exposure

1. Stop intake and revoke relevant sessions/credentials/signed URLs.
2. Identify affected tenant IDs, object keys, processor attempts, and regions.
3. Preserve content-free security logs.
4. Notify incident and customer contacts under contract/law.
5. Rotate credentials and patch access path.
6. Verify containment and deletion where appropriate.
7. Add regression test and complete root-cause analysis.

## Database restore

At least once before live test:

1. Provision an isolated environment.
2. Restore the encrypted backup.
3. Verify tenants, batches, revisions, findings, and queue state.
4. Confirm restored blob references do not expose deleted objects.
5. Reconcile object storage.
6. Record restore time and failures.

## Provider/parser rollout

- Run candidate on validation and holdout sets.
- Compare safety metrics by profile.
- Deploy behind percentage/tenant flag.
- Preserve old adapter/model for rollback during the pilot.
- Store route/version per attempt.

## Export failure

- Export from immutable approved revisions only.
- Retry deterministic generation safely with an idempotency key.
- Neutralize spreadsheet formula injection.
- Verify row counts and totals against approved revisions.
- Never mark exported until the blob is stored and checksum recorded.

## Capacity limits for first live test

- 100 documents per batch.
- 10 pages per visual document.
- 1,000 documents/day/tenant.
- Two concurrent model calls initially.
- One repair attempt/document.
- Configured maximum bytes/file and decompressed archive.

Change limits only after memory, latency, cost, and abuse tests.
