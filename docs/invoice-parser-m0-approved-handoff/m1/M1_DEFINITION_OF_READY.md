# M1 Definition of Ready

| Requirement | Status | Evidence |
|---|---|---|
| Target customer identified | Ready | `pilot/PILOT_PROFILE_V1.md` |
| First workflow frozen | Ready | `M0_DECISION_RECORD.md` |
| Operating language frozen | Ready | English/Latin script |
| Required fields frozen | Ready | `pilot/REQUIRED_FIELDS_V1.yaml` |
| Blocking errors frozen | Ready | `pilot/BLOCKING_ERRORS_V1.yaml` |
| Canonical boundary agreed | Ready | Country-neutral v2 |
| Currency precision requirement known | Ready | ISO minor units; USD/JPY/KWD fixtures |
| Export contract known | Ready | JSON, normalized CSV and XLSX |
| Regional packs excluded from M1 | Ready | `global_generic_v1` only |
| Privacy impact understood | Ready | Content-free M1; tenant/version/retention metadata |
| Corpus plan exists | Ready | `pilot/CORPUS_AND_HOLDOUT_PLAN.md` |
| M1 test fixture list exists | Ready | `m1/fixture_manifest.csv` |
| Rollback/version policy required | Ready | M1-07 first implementation slice |

## Engineering may start when

- repository and CI exist;
- Ruby/Rails/PostgreSQL versions are pinned in the engineering repository;
- `contracts/invoice.schema.json` is copied as the canonical source;
- test fixtures are created before domain implementation; and
- schema changes require review against `REQUIRED_FIELDS_V1.yaml` and the global-core rule.

## Stop conditions

Pause M1 and reopen M0 only if implementation reveals that:

- a required pilot field cannot be represented without a schema major-version change;
- the two pilot profiles require incompatible canonical semantics;
- direct posting is actually required for pilot value;
- source retention cannot satisfy the assumed terms; or
- line-item requirements make the chosen workflow economically unreviewable.
