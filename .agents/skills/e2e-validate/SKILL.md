---
name: e2e-validate
description: Run end-to-end validation of critical user flows using device testing or browser automation
metadata:
  audience: engineers
  scope: iterative-validation
---
# E2E Validate

## When to use
Triggered by `smart-validate` when user flow code, screen navigation, or interaction logic changes. Also triggered manually via `/validate-e2e`. This validates that key user flows work correctly end-to-end on a real device or emulator.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)
```
**/navigation/**/*.kt, **/NavGraph*.kt
**/MainActivity.kt (navigation/flow changes)
**/onboarding/**/*.kt
**/*Screen.kt (screen-level composables with navigation)
**/BluetoothHidConnection*.kt (connection flow)
**/settings/**/*.kt (settings flow changes)
```

## Workflow

### Step 1: Identify affected user flows
1. Analyze changed files to determine which user flows are affected:
   - **Connection flow**: Bluetooth scanning, pairing, connecting, reconnecting.
   - **Onboarding flow**: First-launch experience, permission grants, initial setup.
   - **Input flow**: Touchpad interaction, gestures, keyboard input, media controls.
   - **Settings flow**: Preference changes, theme switching, about screen.
   - **Monetization flow**: Pro upgrade, feature gating, ad display.
   - **Navigation flow**: Screen transitions, back stack behavior, deep links.

### Step 2: Determine validation approach
2. Check available validation tools:
   - **Mobile MCP available** (`mobile_list_available_devices`): Use on-device testing.
   - **ADB available** (`adb devices`): Use ADB-based interaction.
   - **Neither available**: Skip with note recommending device connection.

### Step 3: On-device flow validation (if device connected)
3. If a device is available:
   a. Ensure the debug build is installed (e.g. Android: `./gradlew :app:installDebug`).
   b. Launch the app under test: Android via `mobile_launch_app` with the debug applicationId (fall back to the release id; resolve from the repo's build config); web repos via the browser preview.
   c. Walk through the affected user flow:
      - Use `mobile_list_elements_on_screen` to verify expected UI state at each step.
      - Use `mobile_click_on_screen_at_coordinates` or element interaction to navigate.
      - Use `mobile_take_screenshot` at key checkpoints for evidence.
   d. Verify at each step:
      - Expected screen/elements are visible.
      - No crash or ANR (app remains responsive).
      - Navigation transitions work correctly.
      - State persists across screen changes where expected.
   e. For connection flow changes: verify Bluetooth discovery, pairing dialog, and connected state.
   f. For settings changes: verify preference persists after navigating away and returning.

### Step 4: Component test fallback (no device)
4. If no device/browser is connected, fall back to component-level tests:
   - Run relevant screen tests via the repo's focused test command (e.g. Android: `./gradlew :app:testDebugUnitTest --tests "*<ScreenName>Test*"`).
   - Run navigation tests if they exist: `--tests "*NavigationTest*"`.
   - Run `MainActivityTest` for flow-level integration: `--tests "*MainActivityTest*"`.
   - Note that on-device validation was skipped.

### Step 5: Report
5. Document the flow validation with:
   - Steps taken and results at each step.
   - Screenshots captured (reference by description).
   - Any errors, crashes, or unexpected behavior.
   - Whether the flow completed successfully end-to-end.

## Output format
```
## E2E Validation Results
### Flow tested: [flow description]
### Tool used: Mobile MCP / ADB / Browser preview / Component Tests / Skipped
### Steps
| Step | Action | Expected | Actual | Status |
|------|--------|----------|--------|--------|
| 1 | Launch app | Main screen visible | Main screen visible | PASS |
| 2 | Tap settings | Settings screen opens | Settings screen opens | PASS |
| 3 | Toggle theme | Theme changes | App crashed | FAIL |

### Errors encountered
- [error description with context]

### Screenshots
- [description of captured screenshots]

### Component test results (fallback)
- Status: PASS / FAIL / SKIPPED
- Tests run: [list]

### Verdict: PASS / FAIL
```

## Advisory behavior
During Phase 2, failures are reported and accumulated but do not block commits. They become blocking at Phase 3.

**Exception**: App crashes or ANRs during the flow are immediate blockers.

## Guardrails
- This skill is observation-only during on-device testing. Do not modify files during validation.
- E2E validation is best-effort. If the device/browser is unavailable, degrade gracefully to component tests.
- Do not interact with system dialogs (Bluetooth pairing, permissions) unless they are part of the flow being validated.
- Keep flows focused on what changed -- do not test unrelated flows.
- Minimize device interactions -- navigate only to the affected screen/flow.
- Do not store credentials or sensitive test data in the validation output.
- If the app needs rebuilding for changes to appear, report that and suggest the install command rather than running it.
- E2E runs are slower than unit tests. Only trigger when flow-level code actually changed.
- For Bluetooth connection flow changes, note that full end-to-end validation requires real hardware and a paired host.
