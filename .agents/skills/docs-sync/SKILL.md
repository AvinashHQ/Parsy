---
name: docs-sync
description: Post-ship documentation sync using knowledge mapping to keep docs aligned with code changes
metadata:
  audience: engineers
  scope: documentation
---

> **Hub model (2026-07-03):** durable knowledge lives in the workspace hub at
> `avinashhq_brain/projects/<slug>/` (resolve `<slug>` from the workspace
> `projects.yaml`). Where a repo keeps `docs/knowledge/` files they are pointer
> stubs into the hub — read and write the hub pages wherever this document says
> `docs/knowledge/...`; each stub names its canonical hub page. `index.md` and
> `mapping.md`/`mapping.json` stay repo-side where they exist. GitHub wikis are
> frozen: write wiki-style pages (ADRs, Process-*, Strategy-*) to the hub
> instead, and wikilink any new page from `avinashhq_brain/projects/<slug>.md`.

# Docs Sync

## When to use
Use this skill after code ships (PR merged or release completed) to ensure documentation stays aligned with what changed. Zero-telemetry, local-only workflow.

## Workflow

### Step 1: Identify what changed
1. Run `git diff --name-only <base>...HEAD` or `git log --oneline --name-only <range>` to list all changed files since the last doc sync.
2. Load the repo's knowledge mapping (`docs/knowledge/mapping.json` where it exists; else treat the hub project page's wikilinked pages as the mapping) and cross-reference changed files against it.
3. Build a list of knowledge docs that may need updates.

### Step 2: Review each mapped doc
For each knowledge doc flagged by the mapping:
1. Read the current doc content.
2. Read the relevant changed source files.
3. Determine if the doc's statements are still accurate:
   - Do code paths still match the described architecture?
   - Do testing commands still work as documented?
   - Do configuration defaults match the code?
   - Do feature descriptions match current behavior?
4. Classify each doc as: `current` (no update needed), `stale` (needs update), or `new-content` (new section needed).

### Step 3: Update stale docs
For each `stale` or `new-content` doc:
1. Apply the minimum edit to make the doc accurate.
2. Keep the doc's existing structure and voice.
3. Do not expand docs with speculative future content.
4. Do not duplicate information that already exists in another doc.

### Step 4: Check cross-references
1. Verify `docs/knowledge/index.md` still has correct suggested reading paths.
2. Verify `docs/knowledge/mapping.md` and `docs/knowledge/mapping.json` are consistent with any new files or moved code.
3. If a new knowledge doc was created, add it to the index.

### Step 5: Check non-knowledge docs
If the change was significant (new feature, behavior change, or release):
1. Check if `README.md` feature list or usage instructions need updates.
2. Check if `CHANGELOG.md` has an entry for the change.
3. Check if a `docs/releases/<version>.md` file needs creation or update.
4. Do not update these unless the change is material to users or operators.

## Scope boundaries
| Doc type | When to update |
|----------|---------------|
| `docs/knowledge/*.md` | When mapped source code changed materially |
| `docs/knowledge/mapping.json` | When new source files or patterns were added |
| `docs/knowledge/index.md` | When new knowledge docs were created |
| `README.md` | When user-facing features or setup instructions changed |
| `CHANGELOG.md` | When a release-worthy change shipped |
| `AGENTS.md` | When repo-wide operating rules, commands, or architecture constraints changed |
| `docs/*.md` (non-knowledge) | When the specific operational doc's subject area changed |

## Output format
```
## Docs Sync Report

### Changed files analyzed: N
### Mapped docs checked: N

### Updates applied
| Doc | Status | Change summary |
|-----|--------|---------------|
| docs/knowledge/architecture.md | updated | Added new module description |
| docs/knowledge/testing-playbook.md | current | No update needed |
| README.md | updated | Added new feature to list |

### Cross-reference check
- index.md: current / updated
- mapping.json: current / updated

### No update needed
- [list of docs checked and confirmed current]
```

## Guardrails
- Do not invent content. Only document what the code actually does.
- Do not remove existing doc content unless it is provably wrong.
- Keep edits minimal and factual.
- Preserve the existing voice and structure of each doc.
- Do not create new knowledge docs without adding them to the index and mapping.
- Reference `docs/knowledge/mapping.json` as the source of truth for which docs map to which code areas.
