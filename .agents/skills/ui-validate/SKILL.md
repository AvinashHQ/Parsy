---
name: ui-validate
description: Validate UI rendering, accessibility, and visual correctness after UI changes
metadata:
  audience: engineers
  scope: iterative-validation
---
# UI Validate

## When to use
Triggered automatically by `smart-validate` when UI-related files change, or manually via `/validate-ui`. This skill validates UI correctness at the code and rendering level.

**Distinction from `ui-verify`**: `ui-verify` is a post-implementation on-device verification skill using mobile MCP. `ui-validate` is a broader validation that includes static analysis, accessibility checks, Compose best practices, and optionally delegates to `ui-verify` for device rendering when available.

**Related skills** (repo-local, where present): for deeper Android UI work beyond validation, AirMouse carries `adaptive` (window-size / tablet / foldable / pointer + keyboard layouts), `edge-to-edge` (system-bar/IME insets), and `styles` (Compose Styles API). These are implementation/migration guides, not validation gates.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)

**Path normalization**: patterns use package-suffix shorthand; strip the repo's source-root prefix when matching `git diff --name-only` output.

```
**/*.kt (under ui/, compose/, screen/, *Screen.kt, *Dialog.kt)
app/src/main/res/layout/**, app/src/main/res/drawable/**, app/src/main/res/values/styles.xml, app/src/main/res/values/themes.xml
```

## Workflow

### Step 1: Identify changed UI files
1. Get changed files from `smart-validate` context or run `git diff --name-only <base-branch>...HEAD` (use the base branch from invocation context; defaults to `main` for feature branches, `master` for hotfixes).
2. Filter to UI-relevant files: screens/components, themes, drawables/layouts/stylesheets, string resources affecting UI.

### Step 2: Static analysis
3. Check changed UI files for:
   - Missing `testTag` or semantics on interactive/testable elements.
   - Missing `remember`/`rememberSaveable` for local state (state created inside composable without memoization).
   - Side effects outside `LaunchedEffect`/`DisposableEffect`.
   - Hardcoded strings that should be in `strings.xml`.
   - Missing content descriptions on icons and images.
   - Composables growing too large (heuristic: >100 lines suggests extraction).
   - Missing `Modifier` parameter on public composables.

### Step 3: Accessibility check
4. Check for accessibility issues in changed files:
   - Images/icons without `contentDescription`.
   - Touch targets too small (Material minimum: 48dp).
   - Missing semantics for screen readers.
   - Color contrast issues if theme colors changed (heuristic only -- flag for manual review).

### Step 4: Resource consistency
5. If string resources changed, check:
    - New strings added to `values/strings.xml` exist in key translated locales (deeper locale checks are deferred to `localization-check` at Phase 3 via `review-pipeline`, since the `validator` agent does not run `localization-check`).
   - Placeholder consistency across locales.
   - No string concatenation that breaks localization.

### Step 5: On-device verification (conditional)
6. Check for a connected device (`adb devices`) or usable browser preview.
   - **Device connected**: Delegate to `ui-verify` skill for on-device rendering verification. Report its results.
   - **No device**: Note skip. Static analysis results stand alone.

### Step 6: Component tests
7. If component/rendering tests exist for changed screens, include them in the validation plan:
   - Use the repo's focused test command (e.g. Android: `./gradlew :app:testDebugUnitTest --tests "*<ScreenName>Test*"`).
   - Report test results.

## Output format
```
## UI Validation Results
### Changed UI files
- [file list]

### Static analysis
| Check | Status | Details |
|-------|--------|---------|
| testTag coverage | pass/warn/fail | ... |
| remember usage | pass/warn/fail | ... |
| Side effects | pass/warn/fail | ... |
| Hardcoded strings | pass/warn/fail | ... |
| Content descriptions | pass/warn/fail | ... |

### Accessibility
| Check | Status | Details |
|-------|--------|---------|
| Content descriptions | pass/warn | ... |
| Touch targets | pass/warn | ... |
| Semantics | pass/warn | ... |

### Resource consistency
| Check | Status | Details |
|-------|--------|---------|
| Locale coverage | pass/warn/fail | ... |
| Placeholder consistency | pass/warn/fail | ... |

### On-device verification
- Status: PASS / FAIL / SKIPPED (no device)
- Details: [ui-verify results or skip reason]

### Component tests
- Status: PASS / FAIL / SKIPPED (no tests for changed screens)

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2 (iterative development), failures are reported and accumulated but do not block commits. They become blocking at Phase 3 finalization.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Do not run the full test suite. Only run focused component tests for changed screens.
- Delegate on-device rendering to `ui-verify` -- do not duplicate its workflow.
- Delegate localization checks to `localization-check` -- do not duplicate its workflow.
- Flag accessibility issues as warnings unless they are clear violations (missing contentDescription on interactive elements = fail).
