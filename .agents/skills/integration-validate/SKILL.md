---
name: integration-validate
description: Verify cross-module consistency when changes span multiple packages or modules
metadata:
  audience: engineers
  scope: iterative-validation
---
# Integration Validate

## When to use
Triggered automatically by `smart-validate` when changes span 3+ distinct packages/modules, or manually via `/validate-integration`. This catches cross-cutting issues that per-module validation misses.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)
```
Changes spanning 3+ of these packages:
  bluetooth/, input/, sensor/, ui/, settings/, monetization/,
  review/, update/, navigation/, observability/, onboarding/
Platform manifests + source changes (e.g. AndroidManifest.xml)
MainActivity.kt + any other module changes
```

## Workflow

### Step 1: Map change scope
1. List all changed files and group by package/module.
2. Count distinct packages affected.
3. If fewer than 3 packages, this validation is not needed -- skip with note.
4. Identify the cross-cutting concern (what ties these modules together).

### Step 2: Interface contract verification
5. Check that interfaces/abstractions shared between modules are consistent:
   - Method signatures unchanged on interfaces consumed by other modules.
   - Data classes shared across modules have compatible field changes.
   - Callback signatures match between producer and consumer.
   - Event/state types used in `StateFlow` or channels are consistent.

### Step 3: Dependency flow
6. Verify the dependency graph between changed modules:
   - No circular dependencies introduced.
   - Import paths are correct and not importing internal/private APIs from other modules.
   - Shared state (singletons, managers) accessed consistently.
   - Lifecycle dependencies respected (e.g., Bluetooth connection state consumed by input and UI modules).

### Step 4: State consistency
7. Check cross-module state management:
   - State transitions in one module correctly observed by dependent modules.
   - No race conditions between modules updating shared state.
   - Error states propagate correctly across module boundaries.
   - Settings/configuration changes applied consistently across affected modules.

### Step 5: MainActivity integration
8. If `MainActivity.kt` changed alongside other modules:
   - Verify new wiring/initialization order is correct.
   - Check that new parameters passed to composables/managers match their signatures.
   - Verify lifecycle callbacks handle the new cross-module behavior.

### Step 6: Focused integration tests
9. Run tests that exercise cross-module paths:
   - Use the repo's focused test command targeting entry-point/integration suites (e.g. Android: `--tests "*MainActivityTest*"`).
   - Add `--tests` patterns for any other integration-style tests that cover the changed modules.

## Output format
```
## Integration Validation Results
### Change scope
- Packages affected: N ([list])
- Cross-cutting concern: [description]

### Interface contracts
| Check | Status | Details |
|-------|--------|---------|
| Method signatures | pass/warn/fail | ... |
| Shared data classes | pass/warn/fail | ... |
| Callback compatibility | pass/warn | ... |
| State type consistency | pass/warn | ... |

### Dependency flow
| Check | Status | Details |
|-------|--------|---------|
| Circular dependencies | pass/fail | ... |
| Import correctness | pass/warn | ... |
| Shared state access | pass/warn | ... |

### State consistency
| Check | Status | Details |
|-------|--------|---------|
| State transitions | pass/warn/fail | ... |
| Cross-module races | pass/warn/fail | ... |
| Error propagation | pass/warn | ... |

### MainActivity integration
- Status: PASS / WARN / FAIL / SKIPPED (not changed)

### Integration tests
- Status: PASS / FAIL / SKIPPED

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2, failures are reported and accumulated but do not block commits. They become blocking at Phase 3.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Only trigger when 3+ packages are affected -- smaller changes are handled by per-module validation.
- Do not run the full test suite. Use `MainActivityTest` as the primary integration test.
- Bluetooth state/lifecycle and input pipeline ordering are correctness-critical cross-module concerns -- treat inconsistencies as `fail` not `warn`.
- Do not flag existing cross-module patterns in unchanged code.
