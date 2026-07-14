---
name: perf-validate
description: Check for performance regressions -- main-thread blocking, memory issues, inefficient patterns
metadata:
  audience: engineers
  scope: iterative-validation
---
# Perf Validate

## When to use
Triggered automatically by `smart-validate` when performance-critical code paths change, or manually via `/validate-perf`. This is the iterative validation counterpart to `perf-review` (which runs at Phase 3 as part of the review pipeline).

**Distinction from `perf-review`**: `perf-review` is a comprehensive review-time skill. `perf-validate` is a focused, fast check triggered during iterative development to catch performance regressions early.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)
```
**/*.kt (under bluetooth/, input/, sensor/, motion/)
**/BluetoothHidConnection*.kt, **/BluetoothMouseController*.kt
**/MotionSensorManager*.kt, **/MouseInputController*.kt
**/TouchpadScreen*.kt, **/GestureDetector*.kt
Any file with high-frequency callbacks (sensor listeners, touch handlers, Bluetooth send paths)
```

## Workflow

### Step 1: Identify hot paths
1. Get changed files and classify which are performance-critical:
   - **Touch/gesture input**: sensor callbacks, touch event handlers, gesture recognizers.
   - **Bluetooth send path**: HID report construction, send queue, connection state.
   - **UI rendering**: re-render/recomposition-heavy components, state management.
   - **Background processing**: services, broadcast receivers, coroutine lifecycle.

### Step 2: Main-thread analysis
2. Check changed code for main-thread risks:
   - Blocking I/O on the main thread (file, network, database).
   - `Thread.sleep()` or busy-wait loops.
   - Synchronous Bluetooth operations on the main thread.
   - Heavy computation without dispatching to a background dispatcher.
   - `runBlocking` on the main thread.

### Step 3: Allocation analysis
3. Check hot paths for unnecessary allocations:
   - Object creation inside `onSensorChanged`, `onTouchEvent`, or similar high-frequency callbacks.
   - String concatenation in logging within hot paths (use `AppLog` which handles this).
   - Lambda/closure creation in tight loops.
   - Repeated list/map creation that could be reused.
   - Missing memoization for expensive calculations in UI code (`remember`, `useMemo`, etc.).

### Step 4: Concurrency safety
4. Check for concurrency issues in changed code:
   - Race conditions in Bluetooth connection state transitions.
   - Missing synchronization on shared mutable state.
   - Coroutine scope leaks (launching coroutines without proper scope/cancellation).
   - Send queue ordering violations.
   - Stale state after reconnect.

### Step 5: Battery impact
5. Check for battery-draining patterns:
   - Sensor listeners registered without corresponding unregistration.
   - Wake locks acquired without release.
   - Continuous polling instead of event-driven patterns.
   - High-frequency timers or repeated work without need.

### Step 6: Focused tests
6. Run focused performance-related tests:
   - Use the repo's focused test command (e.g. Android: `./gradlew :app:testDebugUnitTest --tests "*<ChangedClass>Test*"`).
   - Specifically target `BluetoothHidConnectionTest`, `BluetoothMouseControllerTest` if those paths changed.

## Output format
```
## Perf Validation Results
### Changed performance-critical files
- [file list with classification]

### Main-thread risks
| Check | Status | Details |
|-------|--------|---------|
| Blocking I/O | pass/fail | ... |
| Heavy computation | pass/warn | ... |
| runBlocking | pass/fail | ... |

### Allocation in hot paths
| Check | Status | Details |
|-------|--------|---------|
| Object creation | pass/warn/fail | ... |
| String concatenation | pass/warn | ... |
| Missing remember | pass/warn | ... |

### Concurrency safety
| Check | Status | Details |
|-------|--------|---------|
| Race conditions | pass/warn/fail | ... |
| Scope leaks | pass/warn | ... |
| Send ordering | pass/warn | ... |

### Battery impact
| Check | Status | Details |
|-------|--------|---------|
| Listener lifecycle | pass/warn/fail | ... |
| Wake locks | pass/fail | ... |
| Polling patterns | pass/warn | ... |

### Focused tests
- Status: PASS / FAIL / SKIPPED

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2, failures are reported and accumulated but do not block commits. They become blocking at Phase 3.

**Exception**: `runBlocking` on the main thread and unguarded race conditions in Bluetooth state are immediate blockers -- fix before committing.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Focus on the diff -- do not audit unchanged code.
- Prioritize real-time feel and responsiveness over abstraction purity.
- Do not flag performance patterns in test code.
- Bluetooth send path ordering is correctness-critical, not just performance.
- When checking concurrency, reason about the actual threading model (which dispatcher, which scope) rather than flagging all shared state.
