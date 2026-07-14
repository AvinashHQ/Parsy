---
name: changelog
description: Generate CHANGELOG.md entries from branch diff using Keep a Changelog format
metadata:
  audience: engineers
  scope: changelog
---
# Changelog

## When to use
Use this skill to generate or update `CHANGELOG.md` entries based on what changed in the current branch or between two refs. Follows Keep a Changelog format.

## Workflow

### Step 1: Gather changes
1. Run `git log --oneline <base>...HEAD` to list all commits in scope.
2. Run `git diff --stat <base>...HEAD` to understand the scale of changes.
3. Read each commit message and the associated diff to understand what changed.

### Step 2: Classify changes
Categorize each meaningful change into Keep a Changelog sections:

| Section | When to use |
|---------|-------------|
| `Added` | New features, new UI surfaces, new capabilities |
| `Changed` | Modifications to existing behavior, UX improvements, performance improvements |
| `Fixed` | Bug fixes, crash fixes, regression fixes |
| `Removed` | Removed features, deprecated code removal |
| `Security` | Security-related fixes or improvements |
| `Deprecated` | Features marked for future removal |

### Step 3: Write entries
For each change:
1. Write a user-facing description (not implementation details).
2. Keep entries concise — one line per change.
3. Use imperative mood: "Add", "Fix", "Change", not "Added", "Fixed", "Changed" in the entry text.
4. Group related small changes into a single entry when they serve the same user-visible outcome.
5. Skip internal refactors, test-only changes, and CI tweaks unless they affect users or operators.

### Step 4: Place in CHANGELOG.md
1. Read the existing `CHANGELOG.md` to understand the current format and latest version.
2. If an `[Unreleased]` section exists, add entries there.
3. If no `[Unreleased]` section exists, create one at the top.
4. When preparing for a release, rename `[Unreleased]` to `[version] - YYYY-MM-DD`.

### Step 5: Cross-reference release notes
1. If a `docs/releases/<version>.md` exists for the target version, verify consistency.
2. The changelog should be a concise summary; release notes can have more detail.

## Output format
```
## Changelog Update

### Entries generated
## [Unreleased]

### Added
- entry

### Changed
- entry

### Fixed
- entry

### Source commits
- SHA — message (mapped to: section)
- SHA — message (skipped: reason)
```

## Guardrails
- Write for users, not developers. Avoid internal jargon.
- Do not include commit SHAs in the actual changelog entries.
- Do not include test-only or CI-only changes unless they affect the release process.
- Keep the same formatting style as existing entries in `CHANGELOG.md`.
- If `CHANGELOG.md` does not exist, create it with Keep a Changelog header and format.
- Do not fabricate changes. Only document what the commits actually contain.
