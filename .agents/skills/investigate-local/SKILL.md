---
name: investigate-local
description: Systematic root-cause debugging with zero external telemetry
metadata:
  audience: engineers
  scope: debugging
---
# Investigate Local

## When to use
Use this skill when a bug, crash, unexpected behavior, or regression needs systematic root-cause investigation before any fix is applied. Zero-telemetry, local-only workflow.

## Iron law
**No fixes without root cause.** Do not apply speculative patches. Complete the investigation phases first.

## Workflow — Four phases

### Phase 1: Investigate
1. Reproduce or confirm the symptom.
2. Gather evidence:
   - Read relevant source code in the area of the bug.
   - Check `git log` for recent changes to the affected area.
   - If a device is connected, use `adb logcat` filtered to `BluetoothHidConnection`, `MainActivity`, or the relevant tag.
   - Check `adb devices` to confirm target availability.
   - Collect any crash stack traces, ANR traces, or assertion failures.
3. Identify the scope: is this Bluetooth, input, UI, monetization, lifecycle, or cross-cutting?

### Phase 2: Analyze
1. Trace the code path from trigger to symptom.
2. Identify state transitions, race conditions, or ordering issues.
3. Check for known risk patterns:
   - Bluetooth lifecycle: stale state, reconnect cleanup, callback ordering
   - Input paths: queue ordering, main-thread blocking, allocation churn
   - Compose UI: recomposition loops, missing `remember`, lifecycle misuse
   - Permissions: missing runtime checks, denial handling
   - Concurrency: coroutine scope leaks, unstructured threading
4. Cross-reference with `docs/knowledge/debugging-checklist.md`.

### Phase 3: Hypothesize
1. Form a specific root-cause hypothesis with evidence.
2. State what the hypothesis predicts: what should change if the hypothesis is correct.
3. Design a verification test:
   - Identify the smallest test or code probe that would confirm or refute the hypothesis.
   - If a focused unit test can verify, specify the test class and assertion.
   - If only runtime verification works, specify the `adb logcat` filter and expected output.

### Phase 4: Implement
1. Only after the hypothesis is confirmed, apply the smallest correct fix.
2. Write or update a focused test that covers the root cause.
3. Run the focused test to confirm the fix works.
4. Run broader validation if the fix touches shared code (per `smart-validate` escalation rules).
5. Verify no regressions in adjacent code.

## Integration with other skills
- For Bluetooth-specific issues, load `bluetooth-troubleshooting` alongside this skill.
- For Android runtime/device issues, load `android-debug` alongside this skill.
- For performance-sensitive issues in hot paths, reference `docs/knowledge/debugging-checklist.md` performance section.

## Output format
```
## Investigation Report

### Symptom
- Description of the observed behavior
- Reproduction steps (if known)

### Evidence gathered
- Source files examined: file:line
- Recent changes: commit SHA — description
- Logs/traces: relevant excerpts

### Root cause
- Hypothesis: [specific statement]
- Evidence: [what confirms this hypothesis]
- Code location: file:line

### Fix
- What was changed: file:line — description
- Test added/updated: test class.method
- Verification: [command and result]

### Regression check
- Command: ...
- Result: PASS / FAIL
```

## Guardrails
- Do not apply any fix during Phases 1-3.
- Do not add logging or debug instrumentation as a permanent fix.
- Prefer `AppLog` over raw `Log` for any temporary diagnostic logging.
- Do not log sensitive data (MAC addresses, emails, tokens).
- Keep diagnostic work read-only until Phase 4.
- If the root cause is unclear after reasonable investigation, report what is known and what remains unknown instead of guessing.
- Reference `docs/knowledge/debugging-checklist.md` for Bluetooth, runtime, and performance investigation checklists.
