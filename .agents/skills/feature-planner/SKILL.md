---
name: feature-planner
description: Pre-implementation feature planner that interviews the user, explores the codebase, and produces a structured implementation plan
metadata:
  audience: engineers
  scope: planning
---
# Feature Planner

## When to use
Use this skill before starting implementation of a new feature or significant enhancement. It produces a structured plan that covers architecture impact, implementation steps, test strategy, and risk assessment.

This skill is read-only. It does not modify code.

## Workflow -- Four phases

### Phase 1: Interview

Ask the user 3-5 targeted questions to understand the feature. Adapt follow-up questions based on answers -- skip questions that become irrelevant.

**Core questions (always ask):**
1. **User problem**: What user problem does this solve? What is the expected user-visible behavior?
2. **Surface**: Which app surface/screen/module does this belong on? (use the repo's area taxonomy from AGENTS.md or the overlay)
3. **Scope**: What is the expected scope? (UI-only, protocol/contract change, cross-cutting, infrastructure)

**Conditional questions (ask when relevant):**
4. **Contract/protocol**: Does this require new report/schema/API types or contract changes? (Ask when scope touches the repo's contract surfaces)
5. **Monetization/tier gating**: Should this be free or tier-gated? Does it affect ad surfaces or paywall gating? (Ask when the repo has monetization and the feature adds user-visible capability)
6. **Platform interaction**: Does this behave differently across host platforms/browsers/devices? (Ask when the feature involves platform-dependent behavior)
7. **Existing precedent**: Is this similar to something already in the app that can be extended? (Ask when unsure about the right integration point)

**Interview rules:**
- Ask all core questions in one message to reduce back-and-forth.
- Wait for the user's answers before proceeding to Phase 2.
- If answers are vague, ask one round of clarifying follow-ups. Do not ask more than two rounds total.
- Do not assume answers the user has not given.

### Phase 2: Codebase exploration

After the interview, silently explore the codebase to map the feature to existing architecture. Do not ask further questions during this phase.

**Steps:**
1. Read the repo's architecture doc (`docs/knowledge/architecture.md` where it exists, else the AGENTS.md Architecture section and the hub project page).
2. Read the repo's knowledge mapping (`docs/knowledge/mapping.json` where it exists) to identify which knowledge docs relate to the affected areas.
3. Search for existing integration points per affected area — use the "Repo integration map" overlay section when present (stamped from `templates/skill-overlays/feature-planner/<slug>.md`), otherwise locate the area's entry points by searching the module named in AGENTS.md.
4. Look for similar patterns already implemented in the codebase that the new feature can follow.
5. Identify files that should NOT be modified (oversized god-files; prefer helpers or managers — the overlay names known ones).
6. Check the repo's testing playbook (where it exists) to understand which test suites cover the affected areas.

### Phase 3: Plan synthesis

Produce a structured plan document with the following sections:

```
## Feature Plan: <feature name>

### Summary
- What it does (1-2 sentences)
- Target user and use case
- User-visible behavior

### Architecture Impact
- Modules affected: list each module/package with reason
- New files needed: list with purpose
- Existing files modified: list with file:line integration points
- Files to avoid modifying: list with reason
- Dependency graph: which changes depend on which

### Implementation Steps
Ordered todo list. Each step includes:
- Description of what to implement
- Target file(s)
- Complexity estimate: small / medium / large
- Dependencies: which prior steps must complete first

Example format:
1. [small] Add constant/config for new capability -- `<contract or config file>:XX`
2. [medium] Create manager/service class for new feature -- new file
3. [medium] Add UI surface -- new component or extend existing screen
4. [small] Wire manager into the app entry point / DI
5. [small] Add strings/resources for new UI
6. [medium] Write unit tests -- new test class

### Contract and Protocol Considerations
- Contract changes: new report/schema/API types, compatibility, migrations
- Lifecycle impact: reconnect behavior, session handling, pairing/auth flows
- Latency sensitivity: is this on a hot path?
- Skip this section if the feature has no contract/protocol implications.

### UI and UX Approach
- Which screen or surface hosts this feature
- Interaction model: direct manipulation, settings toggle, sheet/modal, etc.
- Accessibility: test tags, content descriptions
- Alignment with UX priorities from AGENTS.md

### Test Strategy
- Existing test suites to extend (with class names)
- New test classes needed
- Minimum coverage approach: pure unit tests first, rendering tests only if rendering matters
- Focused validation command (from the smart-validate routing / projects.yaml commands)
- Live verification plan:
  - If the feature adds or modifies UI: plan `ui-verify` runs to validate rendering (mandatory when a device/browser is available)
  - If the feature affects app launch or navigation flow: plan `on-device-smoke` where the repo has it
  - Note which form factors are relevant

### Risk Assessment
| Risk | Severity | Mitigation |
|------|----------|------------|
| Latency impact on hot path | high/medium/low | ... |
| Resource drain from new background work | high/medium/low | ... |
| Lifecycle/connection regression | high/medium/low | ... |
| Main-thread blocking | high/medium/low | ... |
| Breaking existing behavior | high/medium/low | ... |

### Knowledge Docs
- Which knowledge pages will need updates after implementation
- Whether the repo's knowledge mapping needs new entries

### Localization (repos with localization)
- New string resources needed (list key names and English values)
- Locale impact: does this require glossary updates?

### Open Questions
- Decisions that need the user's input before implementation
- Ambiguities that could not be resolved from the codebase alone
- Alternative approaches considered and why one was preferred
```

### Phase 4: Handoff

After presenting the plan:
1. Ask if the user wants to proceed with implementation.
2. If yes, provide a `task-start`-ready summary:
   - Suggested issue slug (kebab-case, e.g., `media-key-controls`)
   - Suggested branch type (`feat`, `fix`, `chore`)
   - Task summary (1-2 sentences for the draft PR)
   - The implementation steps as a ready-to-use todo list
3. If the user wants changes to the plan, revise the relevant sections.

## Guardrails
- This skill is completely read-only. Do not create, modify, or delete any files.
- Reference specific `file:line` locations when identifying integration points, not vague module names.
- Consult the repo's architecture/debugging/testing knowledge docs during exploration when they exist.
- Do not invent features or scope beyond what the user described.
- Flag clearly when a feature idea conflicts with existing architecture, product direction from AGENTS.md, or UX priorities.
- If the codebase already has the requested feature or a close variant, point that out instead of planning a duplicate.
- Keep implementation steps concrete and ordered -- each step should be independently committable.
- Do not suggest modifying test assertions to accommodate new behavior unless the test is provably wrong.
- Prefer extending existing architectural seams over introducing new patterns unless justified.
- Respect the repo's known god-file rules (see overlay) — prefer helpers, managers, or new files.
