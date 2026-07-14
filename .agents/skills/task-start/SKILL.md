---
name: task-start
description: Bootstrap the draft-first PR lifecycle for a new code-delivery task by creating a branch, opening a draft PR, and recording the tracking anchor
metadata:
  audience: engineers
  scope: task-lifecycle
---
# Task Start

## When to use
Use this skill at the **very beginning** of any code-delivery task -- before writing any implementation code. It executes Phase 1 of the draft-first PR lifecycle defined in `AGENTS.md`.

Code-delivery tasks MUST NOT begin implementation until this skill has completed and a draft PR URL is recorded.

## Inputs
- **Issue ID**: the task identifier (e.g., `AHQ-42`). Required.
- **Slug**: a short kebab-case description of the work (e.g., `quick-switch`, `fix-reconnect`). Required.
- **Branch type**: one of `feat`, `fix`, `chore`, or `hotfix`. Defaults to `feat`.
- **Base branch**: the branch to target. Defaults to `main` for `feat`/`fix`/`chore` and `master` for `hotfix`.
- **Task summary**: one or two sentences describing what will be done and why. Used for the draft PR Summary section.

## Workflow

### 1. Validate inputs
- Confirm the issue ID and slug are provided.
- Determine the branch type and base branch.
- Construct the branch name: `<type>/ahq-<id>-<slug>` (e.g., `feat/ahq-42-quick-switch`).
- **Feasibility pre-flight (when starting from a filed issue).** Read the source issue's labels. If it
  carries `needs-feasibility-review` or `assumption-unverified`, do NOT treat its specifics (protocol/spec
  claims, "no change needed", effort) as settled. First resolve the open architectural question / verify the
  flagged assumptions — consult the issue's cited sources, and for contract/spec claims run the repo's
  `contract-validate` checklist where applicable. Record the resolution in the draft PR Summary. If it needs
  a direction call, escalate to the user before writing code. A `needs-feasibility-review` issue is not
  "ready" until its Feasibility verdict is confirmed. (Safety net for the confident-but-unverified
  spec/feasibility claim reaching implementation.)

### 2. Pre-flight check
Verify the working tree is in a clean state before creating the branch:
```bash
# Abort if uncommitted changes exist
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: uncommitted changes detected. Stash, commit, or discard before starting a new task."
  exit 1
fi
```
Then fetch the latest base branch from the remote:
```bash
git fetch origin <base-branch>
```
Always branch from `origin/<base-branch>`, never from the local `<base-branch>`. Branching from a stale or locally modified base can silently carry unintended changes into the new branch.

### 3. Create the feature branch
```bash
git checkout -b <branch-name> origin/<base-branch>
```

### 4. Make an initial commit
An empty commit is acceptable to anchor the branch:
```bash
git commit --allow-empty -m "chore: open draft PR for <task summary>"
```

### 5. Push the branch
```bash
git push -u origin <branch-name>
```

### 6. Open the draft PR
1. Read the repo's `.github/pull_request_template.md` if present; if the repo has no template, use a plain Summary / Changes / Testing structure.
2. Fill the template in **skeleton form** (draft mode rules from `pr-create` skill):
   - **Summary**: fill with the task summary / planned approach (never leave as "TBD").
   - **Changes**: list the planned changes as bullets prefixed with "WIP:".
   - **Single-choice sections** (risk level, knowledge maintenance, and similar checklists): select the expected option.
   - **Evidence sections** (testing done, edge cases, performance/connectivity notes, screenshots): leave the template's built-in placeholder text unchanged; they are populated at finalize.
   - **Production promotion checklists**: leave all unchecked (unless base branch is `master`).
3. Check for an existing PR on this branch using `gh pr list --head <branch-name>`.
4. If no PR exists, create one as a draft:
   ```bash
   gh pr create --draft --title "<concise task title>" --body "$(cat <<'EOF'
   <skeleton PR body>
   EOF
   )"
   ```
5. If a PR already exists, update it:
   ```bash
   gh pr edit --body "$(cat <<'EOF'
   <skeleton PR body>
   EOF
   )"
   ```

### 7. Record and return
- Return the PR URL, branch name, and base branch.
- Record the PR URL in task tracking (todo list or conversation context).
- The task is now in Phase 1 complete state and ready for implementation (Phase 2).

## What happens next
- **Phase 2 -- Execution**: Each time a todo item is completed:
  1. Run `smart-validate` (focused tests + validation skills for the changed areas). When the repo provides a `validator` subagent, delegate via the Task tool instead of running validation on the main thread.
  2. Update the validation ledger based on the results.
  3. Commit the work with a descriptive message and push.
- **Phase 3 -- Completion**: When all implementation is done:
  1. Resolve any accumulated validation failures from the ledger.
  2. Run pre-finalization validation (lint once, focused tests only -- never the full suite).
  3. **Live UI verification** (when applicable): if UI files changed and a device/browser is available, run `ui-verify`. If not, note the skip. For launch/navigation changes, also consider `on-device-smoke` where the repo has it.
  4. **Mandatory review gate**: run `self-review` (single-area) or `review-pipeline` (multi-area); when the repo provides `self-reviewer`/`review-pipeline` subagents, delegate via the Task tool instead of reviewing on the main thread. Fix any `[fail]` findings and re-run until the verdict is READY.
  5. Invoke the `pr-create` skill in **finalize mode** to re-derive all PR sections from the actual diff, include the self-review verdict, validation results, and UI verification results in the testing evidence, update the PR body, and mark it ready for review with `gh pr ready`.

## Guardrails
- Never skip the draft PR creation. The draft PR is the tracking anchor for the entire task.
- Never start implementation before the draft PR URL is recorded.
- Never branch from local `main` / `master` without fetching first. Always use `origin/<base>` as the branch point.
- If the working tree has uncommitted changes, warn the user and do not proceed until the state is resolved (stash, commit, or discard).
- The draft PR body must use the full PR template structure, not a short custom summary.
- Never auto-check production promotion items for non-`master` PRs.
- Select exactly one risk checkbox and exactly one knowledge-maintenance checkbox.
- If the repo provides a worktree helper script (e.g. `scripts/create_worktree.sh`), prefer using it to create the branch in a dedicated worktree.
- If the branch already exists and has a PR, update the existing PR instead of creating a duplicate.
