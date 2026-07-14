---
name: ci-monitor
description: Check GitHub Actions CI status, interpret failures, and suggest fixes
metadata:
  audience: engineers
  scope: ci-monitoring
---
# CI Monitor

## When to use
Use this skill to check GitHub Actions workflow status for the current branch or a specific PR. It interprets failures, distinguishes real regressions from CI noise, and suggests fixes.

## Workflow
1. Identify the current branch and any associated PR number.
2. Fetch the latest workflow runs using `gh run list --branch <branch> --limit 5`.
3. For each relevant run, check the status of individual jobs:
   - Guardrails (PR body validation, knowledge check)
   - Lint (`lintDebug`, `lintQa`)
   - Core JVM tests
   - UI-focused JVM tests
   - Debug assemble
   - The aggregate `Unit Tests and Debug Build` gate
4. For failed or cancelled runs, perform triage.
5. Report findings and suggest next actions.

## Failure triage

### Step 1: Distinguish cancellation from real failure
- Check if a newer run exists for the same branch. If yes, the older run was likely cancelled by GitHub Actions concurrency rules — not a real failure.
- Check the run's `conclusion` field: `cancelled` vs `failure` vs `timed_out`.

### Step 2: For real failures, fetch logs
- Use `gh run view <run-id> --log-failed` to get failed job logs.
- Parse the output for:
  - Failing test class and method name
  - Assertion failure details (expected vs actual)
  - Build errors (compilation, lint violations, missing resources)
  - OOM or timeout indicators

### Step 3: Classify the failure
| Failure type | Indicators | Suggested action |
|-------------|------------|------------------|
| Test regression | Specific test assertion failure | Fix the failing code, run focused test locally |
| Compilation error | `Unresolved reference`, `Type mismatch` | Fix the compilation issue |
| Lint violation | `LintError`, specific rule name | Fix the lint issue or suppress with justification |
| OOM / memory pressure | `OutOfMemoryError`, long silent gaps | Check for oversized Robolectric Compose suites per testing-playbook.md |
| Timeout | Job exceeded time limit | Investigate test runtime; do not increase timeout as first fix |
| PR body validation | `validate_pr_body` failure | Fix PR body to match template requirements |
| Knowledge check | `validate_knowledge` failure | Update knowledge docs or PR body knowledge-maintenance section |
| Flaky / infrastructure | Intermittent, not reproducible locally | Re-run the workflow; if persistent, investigate |

### Step 4: Suggest local reproduction
- Provide the exact local command to reproduce the failure (from projects.yaml `commands:` / the failing CI step).
- Reference the repo's testing playbook (where it exists) for the focused test command.

## Output format
```
## CI Status Report

### Branch: <branch>
### PR: #<number> (if applicable)

### Latest runs
| Run | Status | Trigger | Duration | Age |
|-----|--------|---------|----------|-----|
| #id | pass/fail/cancelled | push/pr | Xm | Y ago |

### Job breakdown (latest relevant run)
| Job | Status | Details |
|-----|--------|---------|
| Guardrails | pass/fail | ... |
| Lint | pass/fail | ... |
| Core tests | pass/fail | ... |
| UI tests | pass/fail | ... |
| Assemble | pass/fail | ... |
| Gate check | pass/fail | ... |

### Failures (if any)
- Job: <name>
  - Type: <classification>
  - Details: <what failed>
  - Local repro: `<command>`
  - Fix suggestion: <action>

### Recommendation
- Next action for the developer
```

## Guardrails
- This skill is read-only. It does not modify code or re-trigger workflows.
- Distinguish `cancelled` from `failure` before reporting — per testing-playbook.md guidance.
- Never suggest increasing CI timeouts as the first fix.
- Reference existing testing-playbook.md and build-and-variants.md for triage guidance.
- If multiple runs exist, focus on the most recent relevant one.
- When suggesting local reproduction, prefer the smallest focused command.
