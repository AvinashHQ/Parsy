---
name: type-validate
description: Verify the type system is clean -- compilation/typecheck passes, no unsafe type escapes in changed files
metadata:
  audience: engineers
  scope: iterative-validation
---
# Type Validate

## When to use
Triggered automatically by `smart-validate` when any typed source files change, or manually. This is the most frequently triggered validation -- it runs on virtually every code change. Repos without a compiled/typed language run their nearest equivalent (linter/static analysis) or skip with a note.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)
```
any typed source file (*.kt, *.ts, *.java, ...)
**/build.gradle.kts, **/settings.gradle.kts (build configuration)
```

## Workflow

### Step 1: Compilation check
1. Run the repo's compile/typecheck command (e.g. Android: `./gradlew compileDebugKotlin`; TS: `tsc --noEmit`; resolve from projects.yaml `commands:`).
   - If this fails, report the compilation errors immediately. No further checks needed.
   - If this passes, proceed to static analysis.

### Step 2: Type safety analysis
2. Inspect the diff (`git diff <base-branch>...HEAD -- '*.kt'`) for type safety issues (use the base branch from invocation context; defaults to `main` for feature branches, `master` for hotfixes):
   - **Force unwrap (`!!`)**: Flag any new `!!` usage. Check if the invariant is guarded nearby. Unguarded `!!` is a `fail`.
   - **Unsafe casts (`as`)**: Flag new non-null casts. Prefer `as?` with null handling. Unguarded `as` on external data is a `fail`.
   - **Platform types**: Flag new uses of platform types (Java interop without explicit nullability). Prefer adding explicit `?` or `!!` with a guard.
   - **`Any` type**: Flag new uses of `Any` as a type parameter or return type where a specific type would be clearer.
   - **Suppressed warnings**: Flag new `@Suppress` annotations, especially `UNCHECKED_CAST` and `NOTHING_TO_INLINE`.

### Step 3: Public API types
3. Check changed public API surfaces (public/internal functions, properties, classes):
   - Public APIs should have explicit return types (not inferred).
   - Public APIs should document nullability contract.
   - Exposed `StateFlow` should be typed as `StateFlow<T>`, not `MutableStateFlow<T>`.

### Step 4: Build configuration
4. If build files changed (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`):
   - Verify the project still builds (repo build command).
   - Check for dependency version conflicts or resolution issues.

## Output format
```
## Type Validation Results
### Compilation
- Status: PASS / FAIL
- Errors: [compilation errors if any]

### Type safety
| Check | Status | Details |
|-------|--------|---------|
| Force unwrap (!!) | pass/warn/fail | N new occurrences, M unguarded |
| Unsafe casts (as) | pass/warn/fail | ... |
| Platform types | pass/warn | ... |
| Any type usage | pass/warn | ... |
| Suppressed warnings | pass/warn | ... |

### Public API types
| Check | Status | Details |
|-------|--------|---------|
| Explicit return types | pass/warn | ... |
| StateFlow exposure | pass/warn | ... |

### Build configuration
- Status: PASS / FAIL / SKIPPED (no build files changed)

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2 (iterative development), failures are reported and accumulated but do not block commits. They become blocking at Phase 3 finalization. Compilation failures should be fixed immediately regardless of phase.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Compilation check is the critical gate. If it fails, nothing else matters.
- Do not flag existing `!!` usage in unchanged code -- only flag new additions in the diff.
- Use the fastest compile/typecheck-only command rather than a full build unless build files changed.
- A new `!!` with an immediately preceding null/type guard is a `warn`, not a `fail`.
- Do not flag test files for public API type requirements.
