---
name: knowledge-maintenance
description: Keep project knowledge docs, skills, and memory aligned with code changes
metadata:
  audience: maintainers
  scope: knowledge-maintenance
---
# Knowledge Maintenance

## When to use
Use this skill after feature work, bug fixes, release workflow changes, or architecture changes that may affect durable project knowledge.

## Where knowledge lives (hub model, 2026-07-03)
Durable project knowledge lives in the workspace hub: `avinashhq_brain/projects/<slug>.md`
(summary page) and `avinashhq_brain/projects/<slug>/` (deep pages) — resolve `<slug>` from
the workspace `projects.yaml`. Repo-side files are the exceptions:
- `AGENTS.md` / `README.md` — repo rules and setup (always repo-side).
- Some repos keep pointer stubs or mappings under `docs/knowledge/` (e.g. AirMouse's
  `index.md` + `mapping.json`) or repo-side memory by explicit exception (cleanify,
  handsOnLab decisions). Follow the repo's AGENTS.md.
- New wiki-style pages (ADRs, Process-*, Strategy-*) go to the hub, wikilinked from the
  project summary page — never to a frozen GitHub wiki.

## Read first
- The repo's `docs/knowledge/index.md` and `mapping.*` when they exist, else the hub project page.
- `AGENTS.md`

## Workflow
1. Identify changed files and map them to affected knowledge docs (repo mapping file when present, else the hub project page's wikilinked pages).
2. Review whether the change alters architecture facts, build behavior, testing strategy, debugging guidance, release guidance, or product behavior.
3. Update the smallest relevant knowledge docs when facts changed.
4. If no update is needed, capture that conclusion in the PR description.
5. Prefer concise factual edits; avoid duplicating long procedural docs.

## Guardrails
- Keep knowledge pages factual and stable.
- Put repeatable procedures in skills, not in the knowledge base.
- Prefer references to existing detailed docs over duplicating checklists.
- One home per fact (workspace ownership matrix): don't write the same fact to both the repo and the hub.
