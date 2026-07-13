---
description: Create a GitHub issue for this repository
---

Create a GitHub issue for this repository following the workspace issue-authoring
standard (`avinashhq_brain/references/issue-authoring-standard.md` in the AvinashHQ
workspace).

Use the `github-issue` skill workflow.

Optional input:
- if `$ARGUMENTS` is non-empty, use it as the primary source material for the issue title and body
- if `$ARGUMENTS` is empty, infer the issue from the current conversation context only

Requirements:
- check for a closely matching existing open issue before creating a new one
- exactly one `type:*` label and one `priority:p*` label; `area:*` facets as applicable
- acceptance criteria checklist is mandatory on every issue
- UI-affecting issues (`area:ui`) require the committed design mock per the standard (`docs/mocks/<issue-slug>/`)
- link the parent epic as a native sub-issue, or state `standalone` explicitly
- return the issue number and URL
