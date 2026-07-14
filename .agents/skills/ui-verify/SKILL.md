---
name: ui-verify
description: Verify UI changes render correctly on a connected device or browser after a code change
metadata:
  audience: engineers
  scope: ui-verification
---
# UI Verify

## When to use
Use this skill after making UI, layout, theme, or string/resource changes to verify they render correctly on a connected device (Android: mobile MCP) or in the browser (web repos: browser preview). This gives visual confirmation that code changes produce the expected result on real hardware, an emulator, or a live page.

## Workflow

### Phase 1: Identify what changed
1. Run `git diff --name-only` to identify changed UI files (screens/components, themes, resources, styles, strings).
2. Determine which screens are affected by the changes.
3. Note the expected visual outcome of the change (new element, changed text, updated layout, theme adjustment).

### Phase 2: Capture current state
4. Use `mobile_list_available_devices` to confirm a device is connected.
5. Launch the app under test: Android via `mobile_launch_app` with the debug applicationId first (fall back to release; resolve ids from the repo's build config); web repos via the dev-server preview.
6. Navigate to the affected screen if needed:
   - Use `mobile_list_elements_on_screen` to understand the current screen.
   - Use `mobile_click_on_screen_at_coordinates` to navigate (e.g., tap settings, tap a tab).
7. Use `mobile_take_screenshot` to capture the screen showing the changed area.
8. Use `mobile_list_elements_on_screen` to get structured element data.

### Phase 3: Verify
9. Compare the captured state against the expected outcome:
   - **Text changes**: Verify the correct string appears in the element list.
   - **Layout changes**: Check element coordinates and ordering match expectations.
   - **New elements**: Confirm the new element is present with correct properties.
   - **Theme/color changes**: Note visible differences in the screenshot.
   - **Removed elements**: Confirm the element is absent from the element list.
10. Report findings in the output format below.

## Output format
```
## UI Verification

### Changes under test
- Files changed: [list]
- Affected screens: [list]
- Expected outcome: [description]

### Device
- Name: [device name]
- Screen captured: [screen name]

### Verification
| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| [element/behavior] | [what should appear] | [what was found] | PASS/FAIL |

### Screenshots
- [description of what was captured]

### Verdict
- PASS: All UI changes render as expected
- FAIL: [describe what doesn't match]
```

## Guardrails
- Do not modify any files during verification. This skill is observation-only after navigation.
- Minimize taps and interactions — navigate only to the screen that needs verification.
- If the app needs to be rebuilt for the changes to appear, say so and suggest the repo's build/install command.
- Do not interact with system dialogs (Bluetooth pairing, permissions) unless they are part of the UI change being verified.
- For string/localization changes, verify only the current device locale unless asked to check others.
- Report visual discrepancies objectively — do not speculate on causes. If the change looks wrong, defer to `investigate-local` for root-cause analysis.
