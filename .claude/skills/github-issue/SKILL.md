---
name: github-issue
description: Create well-structured GitHub issues per the AvinashHQ issue-authoring standard — typed, labelled, acceptance-criteria-complete, with committed design mocks for UI work and sub-issue links to parent epics.
license: Proprietary
metadata:
  audience: maintainers
  scope: github-issues
  standard: avinashhq_brain/references/issue-authoring-standard.md
---
# GitHub Issue

## When to use
Use this skill whenever creating a GitHub issue — bug, feature/story, task, epic, spike, or chore — in any
active AvinashHQ repo. The canonical rules live in the workspace hub:
`avinashhq_brain/references/issue-authoring-standard.md`. This skill is the enforcement path for
CLI-filed issues (`gh` bypasses the web form templates).

The bar: **an agent must be able to pick the issue up and finish it without guessing.**

## Workflow

1. **Classify.** Pick exactly one type — `epic` / `story` / `task` / `bug` / `spike` / `chore` — plus one
   `priority:p0..p3` and the `area:*` facets. If the change is user-visible UI, `area:ui` is mandatory and
   triggers the design-mock requirement (step 4).
2. **Dedup.** Search open issues (`gh issue list --search`) before filing. If a close match exists,
   comment/extend it instead. Do not file near-duplicates.
3. **Draft the contract.** Every issue carries, in order:
   - **Title** — `[Type] imperative summary`; epic children get an ordinal (`<Epic> 1.2 — …`).
   - **Context / Problem** — what & why; readable with zero conversation history.
   - **Acceptance criteria** — MANDATORY. Concrete `- [ ]` checklist the implementer can self-verify,
     with the verification command (from `projects.yaml` `commands:`) where one exists.
   - **Scope / Out of scope** — explicit boundary.
   - **Design / visual target** — see step 4; write `not-ui` for non-UI work.
   - **Test plan** — the first failing test / regression coverage.
   - **Technical notes** — `file:line` pointers marked *candidate direction (unvalidated)*. State the
     user problem, not a prescribed implementation: PM owns what/why, implementer/CTO owns how.
   - **Dependencies & links** — parent epic, blockers, related issues/PRs, ADRs, memory pages.
   - **Evidence & assumptions** — required for non-trivial or routine-filed issues (see Quality Contract).
   Type extras — epic: success metric + ordered child list; bug: observed/expected/reproduction/evidence +
   regression-test-first criterion; spike: decidable question + timebox + output location.
4. **UI mock pipeline (blocking for `area:ui`).** Build the exact design before filing:
   a. Self-contained HTML/CSS/JS mock (one file, no external deps) with real copy and all relevant states;
      phone-sized viewport and platform look for mobile apps.
   b. Render and screenshot each key state (Playwright/browser tools).
   c. Commit to the target repo at `docs/mocks/<issue-slug>/` (`mock.html`, `state-*.png`) and push.
   d. Embed screenshots in the Design section + link the mock path with "open locally — this is the
      acceptance target."
   e. Bind an acceptance criterion to it: "Implemented UI matches `docs/mocks/<issue-slug>/mock.html`."
   **Refuse to file an `area:ui` issue whose Design section lacks a mock link.**
5. **Gate.** Non-trivial or routine-filed issues run the `issue-evidence-gate` skill before filing:
   BLOCK on any REFUTED claim; UNVERIFIED specifics get demoted to the Assumptions section plus the
   `assumption-unverified` label.
6. **File.** `gh issue create` with title, body, and the full label set.
7. **Attach hierarchy.** Link to the parent epic as a native sub-issue:
   ```bash
   child_id=$(gh api "repos/$OWNER/$REPO/issues/$CHILD" --jq .id)
   gh api -X POST "repos/$OWNER/$REPO/issues/$PARENT/sub_issues" -F sub_issue_id="$child_id"
   ```
   `standalone` work skips this but must say so explicitly in Dependencies & links.
8. **Groom.** Contract complete + evidence clean → add `ready`. Anything missing → `needs-info` with the
   gaps named. Return the issue number and URL.

## Issue Quality Contract (mandatory for routine-filed issues)
Routine/agent-research issues MUST additionally contain, before any routine-specific sections, so a reader
can tell at a glance what was *checked* versus *assumed*:

### Verified facts
Directly confirmed THIS run; each bullet cites its source inline (`file:line`, command + output, or URL).
Uncitable ⇒ it moves to Unverified assumptions.

### Unverified assumptions
Everything believed but not confirmed — exact spec values, API levels, effort estimates, "no change needed"
claims. Each bullet names what would verify it. Empty ONLY if every claim above is cited.

### Evidence
Concrete grounding for the problem itself: `file:line`, a metric, command output, or a citation URL.

### Feasibility verdict
Pick EXACTLY ONE — never leave it implied:
- `feasible-within-current-architecture` — name the modules/seams it plugs into.
- `needs-architecture-change` — name the change AND its migration/compatibility cost.
- `infeasible` — state the platform/API/architecture blocker.
- `uncertain-needs-design` — say what is unknown. Prefer this over a confident guess.

## Guardrails
- Do not create duplicates; extend the existing issue instead.
- Keep titles short, specific, imperative.
- Do not invent reproduction steps or acceptance criteria that were not implied by the request — ask or
  mark `needs-info` instead.
- **Anti-overconfidence:** never state effort, exact spec values, or "no change needed" as fact unless the
  same line carries a citation (`file:line`, command output, or URL). Uncited ⇒ Unverified assumptions.
- Claims about external specs or platform behavior REQUIRE an authoritative citation (URL or in-repo
  authoritative doc). A bare magic number is never self-evidence.
- Every issue gets exactly one `type:*` and one `priority:p*` label.
- Repo-specific rules may be appended below as an overlay section; they extend, never replace, this
  contract.
