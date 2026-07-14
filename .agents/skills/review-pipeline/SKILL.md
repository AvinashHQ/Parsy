---
name: review-pipeline
description: Orchestrate pre-PR quality checks based on what files changed in the current branch
metadata:
  audience: engineers
  scope: review-orchestration
---
# Review Pipeline

## When to use
Use this skill as a pre-PR quality gate at Phase 3 of the draft-first PR lifecycle. It detects which areas of the codebase changed and runs the appropriate review and validation checks in sequence, producing a consolidated pass/flag/fail report.

This is the comprehensive quality gate. For iterative development validation (Phase 2), use `smart-validate` instead.

## Invocation model

When this repo provides a `review-pipeline` subagent (`.claude/agents/review-pipeline.md`), the main agent thread MUST NOT run this skill directly — delegate via the Task tool:

```
Task tool:
  subagent_type: "review-pipeline"
  prompt: "Load the review-pipeline skill. Run the comprehensive pre-PR review for the current branch
           against base branch <base>. Changed files include: <file list if known>.
           Current validation ledger state: <ledger>.
           Return: consolidated report with verdict, all check statuses, blocking issues,
           warnings, and accumulated failure status."
```

The subagent orchestrates all applicable checks internally (self-review, validation skills, domain reviews, knowledge drift). Verbose outputs from each check stay inside the subagent context.

When the subagent returns:
1. The main agent checks the verdict.
2. If READY: proceed to `pr-create` finalize mode.
3. If NEEDS ATTENTION/BLOCKED: fix findings on the main thread, then re-delegate.

Repos without the subagent run this skill directly, keeping per-check output terse.

## Workflow
1. Run `git diff --name-only <base-branch>...HEAD` to list all changed files.
2. Classify changed files using the repo's routing: the "Repo routing" overlay section when present (stamped from `templates/skill-overlays/review-pipeline/<slug>.md`), otherwise the generic routing below plus the repo AGENTS.md Architecture areas.
3. Build a review plan -- only include checks relevant to the changed areas.
4. Execute each applicable check sequentially.
5. Collect any accumulated failures from the `smart-validate` ledger (Phase 2).
6. Produce a consolidated report with verdict.
7. Provide a final recommendation: ready for PR, or needs attention first.

## Review routing

### Core reviews (always applicable)

| Changed area pattern | Check triggered | How it runs |
|---------------------|-----------------|-------------|
| Any production code file | **Self-review** | Run the `self-review` checklist on the diff: correctness, performance, UI/resources, internationalization, security, style, test coverage, knowledge |
| Any file with a knowledge mapping | **Knowledge drift check** | Cross-reference changed files against the repo's knowledge mapping (e.g. `docs/knowledge/mapping.json` where it exists, else the project's hub pages under `avinashhq_brain/projects/<slug>/`) and flag which knowledge docs may need updates |

### Validation skills (generic routing — a repo overlay refines the patterns)

| Changed area kind | Check triggered |
|---|---|
| Any typed source file | `type-validate` |
| UI / view / component files | `ui-validate` (delegates to `ui-verify` when a device/browser is available) |
| API client / network code | `api-validate` |
| Performance-critical paths (per AGENTS.md) | `perf-validate` |
| Dependency manifests / auth / security surfaces | `security-validate` |
| Data models / schemas / serialized contracts | `contract-validate` |
| Changes spanning 3+ modules | `integration-validate` |
| Navigation / user-flow code | `e2e-validate` (degrades to component tests without a device) |

### Domain-specific reviews

Run the deeper domain reviews the repo actually has (check its skill catalog): e.g. `perf-review`, `localization-check`, `monetization-review` for the Android apps. Test-only changes get a **test quality check** (descriptive names, meaningful assertions, no coverage-weakening workarounds); build/workflow changes get a **build safety check** (variant logic, plugin gating, signing/deploy config boundaries intact).

## Execution order
1. **Self-review** (always runs first -- quick diff scan)
2. **Type validation** (fast compilation + type safety check)
3. **UI validation** (if UI files changed -- includes `ui-verify` delegation)
4. **API validation** (if API files changed)
5. **Contract validation** (if data model/schema files changed)
6. **Performance validation** (if perf-critical files changed)
7. **Security validation** (if deps/auth/manifest changed)
8. **Integration validation** (if 3+ modules changed)
9. **E2E validation** (if flow code changed and device available)
10. **Domain reviews** (whichever the repo has, if applicable)
11. **Build safety check** (if applicable)
12. **Knowledge drift check** (always runs last)
13. **Accumulated failure check** (collect unresolved Phase 2 failures from `smart-validate` ledger)

## Output format
```
## Review Pipeline Report

### Changed areas
- [area]: N files

### Checks executed
| Check | Status | Key findings |
|-------|--------|-------------|
| Self-review | pass/warn/fail | ... |
| Type validation | pass/warn/fail | ... |
| UI validation | pass/warn/fail/skipped | ... |
| API validation | pass/warn/fail/skipped | ... |
| Contract validation | pass/warn/fail/skipped | ... |
| Performance validation | pass/warn/fail/skipped | ... |
| Security validation | pass/warn/fail/skipped | ... |
| Integration validation | pass/warn/fail/skipped | ... |
| E2E validation | pass/warn/fail/skipped | ... |
| Domain reviews | pass/warn/fail/skipped | ... |
| Build safety | pass/warn/fail/skipped | ... |
| Knowledge drift | pass/warn/fail | ... |

### Accumulated failures (from Phase 2 smart-validate)
- [fail] description -- from todo #N (resolved/unresolved)
- (none) -- all clear

### Blocking issues
- [fail] description -- file:line

### Warnings
- [warn] description -- file:line

### Verdict: READY / NEEDS ATTENTION / BLOCKED
```

### Verdict definitions
- **READY**: no `[fail]` findings and no unresolved accumulated failures. Proceed to `pr-create` finalize mode.
- **NEEDS ATTENTION**: `[fail]` findings or unresolved accumulated failures that can be fixed quickly. Fix and re-run.
- **BLOCKED**: critical findings requiring significant rework.

## Guardrails
- Never skip performance review/validation for the repo's performance-critical areas (per AGENTS.md / overlay).
- Never skip localization check for string resource changes (where the repo has one).
- Never skip domain reviews for their mapped areas (billing, ads, remote config, etc.).
- Never skip security validation for dependency or manifest changes.
- Never skip type validation when any typed source file changed.
- If UI files changed and a device/browser is available, UI verification is mandatory. If not available, auto-skip with a note but do not block the pipeline.
- For changes affecting app launch or navigation flow, suggest running `on-device-smoke` (where the repo has it) in addition to `ui-verify` and `e2e-validate`.
- Report all results including passes -- full transparency.
- Do not auto-fix issues found. Report them for the developer to address.
- If no production code changed (docs-only, workflow-only), report that and skip code reviews.
- Unresolved accumulated failures from Phase 2 `smart-validate` are blocking at Phase 3. They must be resolved before the verdict can be READY.
- Validation skills that overlap with domain-specific reviews (e.g., `perf-validate` and `perf-review` on the same hot path) should both run. Validation provides structured pass/fail checks; the domain review provides deeper architectural analysis. They are complementary, not redundant.
