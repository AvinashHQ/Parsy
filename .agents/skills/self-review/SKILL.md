---
name: self-review
description: Pre-PR diff review that catches common issues before creating a pull request
metadata:
  audience: engineers
  scope: pre-pr-review
---
# Self Review

## When to use
This skill is a **mandatory gate** in Phase 3 of the draft-first PR lifecycle. It must be run **before** invoking `pr-create` in finalize mode or marking a PR ready for review.

- For **single-area changes**: run this skill (delegated to the `self-reviewer` subagent where the repo provides one — see Invocation model below).
- For **multi-area changes** (e.g., protocol + UI, billing + strings): use `review-pipeline` instead, which orchestrates this skill plus area-specific checks.

This is a read-only review that produces a structured checklist -- it does not modify code. If the verdict is **NEEDS ATTENTION** or **BLOCKED**, fix the flagged `[fail]` issues and re-run until the verdict is **READY** before proceeding to finalization.

## Invocation model

When this repo provides a `self-reviewer` subagent (`.claude/agents/self-reviewer.md`), the main agent thread MUST NOT run this skill directly — delegate via the Task tool:

```
Task tool:
  subagent_type: "self-reviewer"
  prompt: "Load the self-review skill. Review the current branch diff against base branch <base>.
           Return: structured verdict (READY/NEEDS ATTENTION/BLOCKED), category statuses,
           and all findings with file:line references."
```

The subagent reads the full diff, scans against the checklist, and returns a structured report. This keeps the verbose diff content and analysis out of the main conversation context.

When the subagent returns:
1. The main agent checks the verdict.
2. If READY: proceed to `pr-create` finalize mode.
3. If NEEDS ATTENTION/BLOCKED: fix the `[fail]` findings on the main thread, then re-delegate to self-reviewer.

Repos without the subagent run this skill directly.

## Workflow
1. Run `git diff <base-branch>...HEAD` to get the full diff for the current branch.
2. Run `git diff --name-only <base-branch>...HEAD` to list all changed files.
3. Scan the diff against the checklist below, plus the "Repo checklist" overlay section when present (stamped from `templates/skill-overlays/self-review/<slug>.md`).
4. For each item, report `pass`, `warn`, or `fail` with specific `file:line` references.
5. Produce a summary verdict: READY, NEEDS ATTENTION, or BLOCKED.

## Checklist

### Correctness
- No new unchecked assertions / force-unwraps without an immediately preceding null/state guard.
- No silent exception swallowing — exceptions are handled, logged via the repo's logging facility, or reported via telemetry.
- Lifecycle/stateful resources (connections, subscriptions, watchers) include cleanup and reconnect/stale-state consideration.
- Permission- or capability-sensitive code checks availability before use.
- New public APIs have explicit types.

### Performance
- No heavy work on the main/UI thread or request path (disk I/O, network, blocking calls).
- No unnecessary object creation in high-frequency callbacks or hot paths (the repo's AGENTS.md / overlay names them).
- No excessive logging in hot paths.

### UI and resources
- New user-visible strings live in the repo's resource/localization system when it has one, not hardcoded.
- New UI elements carry stable test hooks (test tags / ids) when they need reliable test interaction.
- Components stay stateless when practical; state and callbacks passed in from higher layers.
- Side effects go through the framework's sanctioned mechanism, not ad hoc lifecycle hacks.
- When UI files are modified, live verification via `ui-verify` should be run if a device/browser is available. Flag as `[warn]` if UI files changed but no verification evidence exists.

### Internationalization (repos with localization)
- No hardcoded user-visible strings in code — use the resource system.
- No string concatenation for building user-visible messages — use format strings with positional placeholders.
- No conditional pluralization in code — use the resource system's plural support.
- Layout direction uses logical start/end, not left/right, where the platform supports RTL.
- New strings added to the base locale have matching keys in other locale files, or flag as `[warn]`.
- Product and brand names remain untranslated in all locale files touched.

### Security and privacy
- No sensitive data in logs (identifiers, emails, tokens, secrets).
- Use the repo's sanctioned logging wrapper over raw logging where one exists.
- No new secrets or credentials committed.

### Style consistency
- Imports are explicit and logically grouped; no mass reordering of unrelated imports.
- Naming follows repo conventions.
- Visibility defaults to the narrowest scope; widened only when needed.
- Code style matches the surrounding file, not an externally imposed standard.

### Test coverage
- Changed logic has corresponding test coverage or an explanation of why not.
- No test modifications that weaken existing assertions without justification.
- Test names are descriptive.

### Knowledge and docs
- Check the repo's knowledge mapping (e.g. `docs/knowledge/mapping.json` where it exists, else the project's hub pages) — if changed files are mapped, the linked knowledge docs may need review.
- New features or behavior changes noted for the PR description.

## Output format
```
## Self-Review Results

### Verdict: READY / NEEDS ATTENTION / BLOCKED

| Category | Status | Details |
|----------|--------|---------|
| Correctness | pass/warn/fail | ... |
| Performance | pass/warn/fail | ... |
| UI and resources | pass/warn/fail | ... |
| Internationalization | pass/warn/fail | ... |
| Security and privacy | pass/warn/fail | ... |
| Style consistency | pass/warn/fail | ... |
| Test coverage | pass/warn/fail | ... |
| Knowledge and docs | pass/warn/fail | ... |

### Issues found
- [fail] file:line — description
- [warn] file:line — description
```

### Verdict definitions
- **READY**: no `[fail]` findings. `[warn]` items should be noted but do not block finalization. Proceed to `pr-create` finalize mode.
- **NEEDS ATTENTION**: one or more `[fail]` findings that can be fixed quickly. Fix the issues and re-run before proceeding.
- **BLOCKED**: critical findings (e.g., secrets committed, data leak in logs, correctness-breaking lifecycle bug) that require significant rework before the PR can proceed.

## Guardrails
- This skill is read-only. It does not modify code.
- This skill is **mandatory** before `pr-create` finalize mode. The `pr-create` skill will refuse to finalize if no passing self-review verdict exists.
- Report all findings including passes -- full transparency.
- Do not block on style-only warnings if correctness and performance pass.
- Keep findings actionable with specific file and line references.
- The verdict must be one of: READY, NEEDS ATTENTION, or BLOCKED. Never omit the verdict.
