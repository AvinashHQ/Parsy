---
name: quick-fix-cycle
description: Iterative test-fix-retest loop that runs a focused test, fixes failures, and repeats until green
metadata:
  audience: engineers
  scope: iterative-fix
---
# Quick Fix Cycle

## When to use
Use this skill when you have a failing test or a failing validation skill result and want to iterate quickly: identify the failure, fix the production code, re-run, and repeat until green.

This skill handles two types of failures:
- **Test failures**: a focused test command fails with assertion or runtime errors.
- **Validation skill failures**: a validation skill (`type-validate`, `perf-validate`, `security-validate`, etc.) reported `[fail]` findings that need to be resolved.

## Workflow
1. Accept a target. This can be:
   - A **test target** (class or method name). If not provided, detect from recently changed files using the `smart-validate` decision matrix.
   - A **validation failure** from a validation skill (e.g., `[fail] blocking call on the main thread -- SomeHotPath:142` from `perf-validate`).
2. Run the focused test command (tests run on the main thread since their output drives the next fix). For validation skill re-checks, **delegate to the `validator` subagent** (see step 6).
3. If the test/validation passes on first run, report success and stop.
4. If it fails:
   a. Parse the failure output:
      - For test failures: extract the failing test method name, assertion failure (expected vs actual), and relevant stack trace.
      - For validation failures: extract the `[fail]` finding, the file:line reference, and the validation skill that reported it.
   b. Read the failing test code or the relevant source code to understand what is being asserted/checked.
   c. Read the production code under test to understand the bug or anti-pattern.
   d. Apply the smallest correct fix to the production code.
    e. Re-run the same focused test (on the main thread) or **delegate validation skill re-check to the `validator` subagent** (see step 6).
   f. If it passes, continue to step 5.
   g. If it still fails, repeat from step 4a (up to max iterations).
5. After the focused test passes, run one level broader to check for regressions:
    - Use the `smart-validate` routing (repo overlay or AGENTS.md areas) to pick the adjacent test suite for the touched area.
    - If the fix was in a specific feature, run that feature's test suite.
    - **Do not run the full test suite.** CI handles the full suite after the PR is marked ready for review. If the fix touched shared code, combine focused test patterns for each potentially affected area.
6. If the fix resolved a validation skill failure, **delegate re-validation to the `validator` subagent** via the Task tool. The subagent re-runs the specific validation skill and reports whether the `[fail]` finding is cleared. The main agent then updates the `smart-validate` validation ledger to mark the failure as resolved. Do not run validation skills directly on the main thread.
7. Report the outcome.

## Iteration limits
- Maximum 5 fix iterations per cycle.
- If the test still fails after 5 attempts, stop and report:
  - What was tried
  - What the remaining failure is
  - A hypothesis for the root cause
  - Suggested next steps for the developer

## Output format
```
## Fix Cycle Results

### Target: [test class/method or validation skill finding]
### Type: test failure / validation failure
### Iterations: N / 5
### Final status: GREEN / STUCK

| Iteration | Failure | Fix applied | File:line |
|-----------|---------|-------------|-----------|
| 1 | expected X got Y | changed Z | file:42 |
| 2 | ... | ... | ... |

### Regression check
- Command: ...
- Result: PASS / FAIL

### Validation re-check (if applicable)
- Skill: [validation skill name]
- Previous finding: [fail] description
- Re-run result: PASS / FAIL
- Ledger updated: yes / no

### Summary
- Total files modified: N
- Total lines changed: N
- Regression status: clean / issues found
```

## Guardrails
- Never modify the test itself to make it pass unless the test is provably wrong (wrong assertion, outdated expectation, testing removed behavior).
- If the test needs to change, explain why before modifying it.
- Prefer the smallest diff that fixes the failure.
- Do not broaden to the full suite; combine focused test patterns when the fix crosses module boundaries. CI runs the full suite post-PR.
- Do not run multiple test invocations in parallel in the same worktree.
- If a fix introduces a new import or dependency, verify it matches repo conventions.
- After the cycle completes, list all files modified so the developer can review.
