---
name: pr-create
description: Create or update a pull request with full template compliance, diff analysis, and validation evidence
metadata:
  audience: engineers
  scope: pr-creation
---
# PR Create

## When to use
Use this skill when creating or updating a pull request for the current branch. It supports two modes:

- **Draft mode**: Used at the start of a code-delivery task to open a draft PR with a skeleton template body. This gives reviewers early visibility and creates a tracking anchor for incremental work.
- **Finalize mode**: Used at task completion to re-derive all PR template sections from the actual diff, update the PR body, and mark it ready for review.

## Workflow

### Draft mode (task start)
1. Confirm the current branch and its base branch (`main` for features, `master` for hotfixes).
2. Read the repo's `.github/pull_request_template.md` if present for the required PR body structure; repos without a template use a plain Summary / Changes / Testing structure.
3. Fill the template in skeleton form:
   - **Summary**: one or two sentences describing the planned approach and why the change is needed.
   - **Changes Introduced**: planned changes as bullets prefixed with "WIP:".
   - **Risk Level**: select the expected risk checkbox based on the anticipated change areas.
   - **Areas for Review**: check the boxes matching the expected change areas.
   - **Knowledge Maintenance**: select the expected option.
   - **All other sections** (Testing Done, Edge Cases, Performance Impact, Connectivity Notes, Known Limitations, Screenshots): leave the template's built-in placeholder text as-is in draft PRs (do not replace it with custom WIP markers). Fully populate these sections during finalize mode before marking the PR ready for review.
   - **Production Promotion Checklist**: leave all unchecked (unless targeting `master`).
4. Check for an existing PR on this branch using `gh pr list --head <branch>`.
5. If no PR exists, create one as a draft:
   ```bash
   gh pr create --draft --title "<concise task title>" --body "$(cat <<'EOF'
   <skeleton PR body>
   EOF
   )"
   ```
6. If a PR already exists, update it with a heredoc:
   ```bash
   gh pr edit --body "$(cat <<'EOF'
   <skeleton PR body>
   EOF
   )"
   ```
7. Return the PR URL and branch.

### Finalize mode (task completion)
1. Confirm the current branch and its base branch (`main` for features, `master` for hotfixes).
2. **Validation ledger check** (accumulated failures from Phase 2):
   - Review the `smart-validate` validation ledger from the current task session.
   - If any unresolved `[fail]` results remain from Phase 2 validation runs, halt finalization. The caller must resolve all accumulated failures (via `quick-fix-cycle` or manual fix) and re-validate before proceeding.
   - Record all accumulated validation results (resolved and warnings) for inclusion in Testing Done.
3. **Pre-finalization validation** (run exactly once, not repeated):
   - **Lint**: run the repo's lint command (projects.yaml `commands:` / AGENTS.md) **once**. Skip if lint already passed earlier in the task and no production code changed since.
   - **Tests**: run only focused tests relevant to the changed areas (use the `smart-validate` decision matrix). **Never run the full test suite** as a pre-PR gate when focused filtering exists; CI handles the full suite after the PR is marked ready.
   - If both lint and focused tests pass, proceed. Do not add extra validation rounds.
4. **Mandatory self-review gate** (must pass before proceeding):
   - Check whether a self-review has already been run in this session. If not, halt finalization and instruct the caller to **delegate** to the `self-reviewer` subagent (single-area) or `review-pipeline` subagent (multi-area) via the Task tool first. Do not run review skills on the main thread.
   - If the most recent review verdict was **NEEDS ATTENTION** or **BLOCKED**, halt finalization. The caller must fix the flagged `[fail]` issues, re-delegate the review to the appropriate subagent, and invoke finalize mode again only after achieving a **READY** verdict.
   - If the verdict is **READY** (possibly with `[warn]` items), proceed. Record the verdict and any notable warnings for inclusion in Testing Done.
5. Run `git diff --stat` and `git log` against the base branch to understand the full change scope.
6. Read the repo's `.github/pull_request_template.md` if present for the required PR body structure.
7. Analyze changed files and classify by the repo's major areas — use the `smart-validate` routing (repo overlay or AGENTS.md Architecture section) as the area taxonomy, plus the cross-cutting ones:
   - UI / views / components (flag for live verification)
   - Build / CI / dependency manifests
   - String resources / localization
   - Tests
   - Documentation / knowledge
8. Fill every section of the PR template with concrete details from the diff:
   - Summary: what problem this solves and why the change is needed
   - Changes: bullet list of actual changes (remove any "WIP:" prefixes)
   - Risk level: auto-select based on changed areas (performance/protocol-critical = High, logic = Medium, UI/docs = Low)
   - Area checkboxes: check the boxes matching the classified areas
   - Testing evidence: list which tests were run and their results, **plus the self-review verdict and any notable findings**, **plus validation skill results from the smart-validate ledger** (type-validate, ui-validate, perf-validate, etc. with pass/warn/fail per skill). When UI files were changed, include `ui-verify` results (device/browser, PASS/FAIL table) or "live UI verification skipped — no device available". When E2E validation was run, include the flow tested and step results.
   - Edge cases: derive from the diff context
   - Knowledge maintenance: check whether mapped knowledge docs need updates
   - Performance/connectivity notes: required when the diff touches areas the repo template marks as required
   - Screenshots: when `ui-verify` was run, reference or attach the captured screenshots
9. Update the PR body with the finalized content:
   ```bash
   gh pr edit --body "$(cat <<'EOF'
   <finalized PR body>
   EOF
   )"
   ```
10. Mark the PR ready for review:
   ```bash
   gh pr ready
   ```
11. Return the PR URL, branch, and validation evidence summary (including self-review verdict).

## Guardrails
- Never replace the template with a short custom summary.
- Never auto-check production promotion items for non-`master` PRs.
- Leave unchecked checklist items visible when they do not apply.
- Non-`master` PRs must leave every production promotion checkbox unchecked.
- Select exactly one risk checkbox and exactly one knowledge-maintenance checkbox.
- In draft mode, the Summary must contain the planned intent, not a placeholder like "TBD".
- In finalize mode, re-derive all sections from the actual diff; do not leave any "WIP" markers.
- **Never mark a PR ready for review without a passing self-review (or review-pipeline) verdict.** If no review has been run, halt finalization and require the caller to run one first.
- **Never mark a PR ready for review with unresolved validation failures.** Check the `smart-validate` validation ledger for accumulated `[fail]` results from Phase 2. All must be resolved before finalization can proceed.
- Never mark a PR ready for review without running the full template fill in finalize mode.
- **Never run the full test suite** as a pre-PR validation step when focused filtering exists. Only run focused tests for changed areas. CI handles the full suite.
- **Run lint at most once** per finalization. Do not re-run lint if it already passed and no production code changed since.
- Include the self-review verdict and any notable `[warn]` findings in the Testing Done section of the finalized PR body.
- When UI files are in the diff, include UI verification evidence in the testing section: either `ui-verify` results or a skip note explaining why (no device/browser available).
- Treat the `gh pr ready` transition as the review handoff; keep the task `in_review` after this point.
- If a PR already exists for this branch, update it instead of creating a duplicate.
