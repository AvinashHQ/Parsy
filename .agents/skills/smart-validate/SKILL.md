---
name: smart-validate
description: Detect what changed on the current branch and run the minimum validation needed
metadata:
  audience: engineers
  scope: smart-validation
---
# Smart Validate

## When to use
Use this skill to validate the current branch with the smallest relevant test, lint, and validation skill commands. It detects what changed, routes to the appropriate validation skills, runs focused tests, and tracks results across iterations.

This is the **routing brain** of the iterative validation system. It runs automatically after each todo completion in Phase 2 of the draft-first PR lifecycle.

## Invocation model

When this repo provides a `validator` subagent (`.claude/agents/validator.md`), the main agent thread MUST NOT run this skill directly — delegate via the Task tool:

```
Task tool:
  subagent_type: "validator"
  prompt: "Load the smart-validate skill. Run validation for the current branch against base branch <base>.
           Current validation ledger state: <ledger>.
           Return: structured validation results, updated ledger entries, and recommendation."
```

The subagent executes all validation skills internally (type-validate, ui-validate, etc.), runs focused tests, and returns a single structured result to the main thread. This keeps verbose build output, diff analysis, and device interaction out of the main conversation context.

When the subagent returns:
1. The main agent updates the validation ledger (todo list or conversation notes).
2. The main agent communicates key findings to the user concisely.
3. The main agent decides next action: commit, fix, or escalate.

Repos without a validator subagent run this skill directly, keeping output summaries terse.

## Workflow
1. Run `git diff --name-only <base-branch>...HEAD` to list all changed files.
2. Classify each changed file into one or more areas using the decision matrix below.
3. Build the minimum validation plan: list of validation skills + focused test commands.
4. Execute each validation sequentially (not in parallel within the same worktree).
5. Report results per command and per validation skill: pass, warn, or fail with details.
6. Accumulate failures across iterations for Phase 3 finalization tracking.

## Decision matrix

Resolve this repo's routing from two sources, in order:

1. **Repo routing overlay** — when a "Repo routing" section is appended below
   (stamped by skill-sync from `templates/skill-overlays/smart-validate/<slug>.md`
   in the workspace), use its tables verbatim: they map this repo's paths to
   focused test commands and validation skills.
2. **Registry fallback** — otherwise derive the plan from the workspace
   `projects.yaml` `commands:` entry for this repo (test/lint/build) plus the
   repo AGENTS.md Commands and Architecture sections. Run the `test` command
   focused to the changed area whenever the runner supports filtering
   (`--tests` patterns, per-file rspec/jest paths, etc.); run `lint` once; and
   route validation skills with the generic table:

| Changed file kind | Validation skills triggered |
|---|---|
| Any typed source file | `type-validate` (compilation + type safety) |
| UI / view / component files | `type-validate` + `ui-validate` (+ `ui-verify` when a device or browser is available) |
| API client / network code | `type-validate` + `api-validate` |
| Data models / schemas / serialized contracts | `type-validate` + `contract-validate` |
| Performance-critical paths (per AGENTS.md) | `type-validate` + `perf-validate` |
| Dependency manifests / auth / security surfaces | `type-validate` + `security-validate` |
| Changes spanning 3+ distinct modules | add `integration-validate` |
| Navigation / user-flow code | add `e2e-validate` (degrades to component tests without a device) |
| Test files only | run the changed tests directly; no validation skills |
| Docs / knowledge only | no code validation needed |

**Precedence rule**: evaluate patterns from most specific to least specific. Test-only and docs-only changes are checked first — if all changed files match those categories, skip validation skills entirely. The catch-all "any typed source file → type-validate" applies only to files not already matched by a more specific pattern.

## Escalation rules
- **Never run the repo's full test suite** as a pre-PR validation step when focused filtering exists. CI handles the full suite after the PR is marked ready for review.
- If more than 5 production files changed across 3+ areas, combine focused test patterns for each affected area into a single test invocation. Do not fall back to the full suite.
- If focused tests fail, report immediately without escalating.
- If only documentation, knowledge docs, or workflow files changed, report that no code validation is needed.
- **Lint**: run the repo's lint command **once** per task. Do not re-run lint if it already passed unless production code changed after the last lint run.
- **Validation skills without device**: `ui-validate` and `e2e-validate` degrade gracefully when no device is connected. They run static analysis and component tests but skip on-device rendering.

## Accumulation and ledger

Track all validation results across todo completions within the same task. Maintain a running ledger:

```
### Validation Ledger
| Todo # | Validations run | Results | Unresolved failures |
|--------|-----------------|---------|---------------------|
| 1 | type-validate, ui-validate | PASS, WARN | [warn] missing testTag |
| 2 | type-validate, perf-validate | PASS, FAIL | [fail] blocking call on main thread |
| 3 | type-validate | PASS | -- |
```

**Accumulation rules**:
- `pass` results are recorded but do not persist as concerns.
- `warn` results are noted but do not block Phase 3 finalization.
- `fail` results accumulate and **must be resolved before Phase 3 finalization**. The `pr-create` skill in finalize mode checks this ledger.
- When a `fail` is fixed (via `quick-fix-cycle` or manual fix), re-run the specific validation that failed. If it passes, mark the failure as resolved in the ledger.
- Immediate blockers (secrets in source, main-thread blocking in hot paths, crashes) should be fixed before committing, regardless of phase.

## Output format
```
## Validation Results

### Changed areas detected
- [area]: N files

### Validation plan
1. skill/command — reason
2. skill/command — reason

### Results
| Validation | Result | Key findings |
|-----------|--------|-------------|
| type-validate | PASS/WARN/FAIL | ... |
| ui-validate | PASS/WARN/FAIL/SKIPPED | ... |
| perf-validate | PASS/WARN/FAIL/SKIPPED | ... |
| Focused tests | PASS/FAIL | command, duration |

### Accumulated failures (unresolved from this task)
- [fail] description — from todo #N
- (none) — all clear

### Recommendation
- Continue development / Fix before proceeding / Ready for Phase 3
```

## Guardrails
- Never run multiple test invocations in parallel in the same worktree.
- Do not run the full suite as first choice — or at all when focused filtering exists. CI runs the full suite after the PR is marked ready.
- Do not suppress or skip validation for risky areas.
- If the branch has no code changes (docs-only), say so and skip the build tooling entirely.
- When UI files changed, check for a connected device/browser. If one is detected, include `ui-verify` in the validation plan. If not, note the skip but do not block.
- Validation skills are advisory during Phase 2 (failures reported, accumulated, but don't block commits). They become blocking at Phase 3 finalization.
- `type-validate` failures (compilation errors) should always be fixed immediately regardless of phase.
- `security-validate` findings about secrets in source code should always be fixed immediately regardless of phase.
