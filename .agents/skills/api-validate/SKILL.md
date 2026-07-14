---
name: api-validate
description: Validate API client contracts, response models, and network layer after API changes
metadata:
  audience: engineers
  scope: iterative-validation
---
# API Validate

## When to use
Triggered automatically by `smart-validate` when API/network-related files change, or manually. Validates the API client layer (client interfaces, response models, network configuration) and, in server repos, endpoint contracts.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)

**Path normalization**: patterns use package-suffix shorthand; strip the repo's source-root prefix when matching `git diff --name-only` output.

```
**/*.kt (under api/, network/, retrofit/, data/remote/)
**/ApiService*.kt, **/RetrofitClient*.kt, **/NetworkModule*.kt
**/model/*Response.kt, **/model/*Request.kt, **/dto/**
```

## Workflow

### Step 1: Identify changed API files
1. Get changed files from `smart-validate` context or run `git diff --name-only <base-branch>...HEAD` (use the base branch from invocation context; defaults to `main` for feature branches, `master` for hotfixes).
2. Filter to API-relevant files: Retrofit interfaces, response/request models, network configuration, interceptors.

### Step 2: Contract consistency
3. Check changed API files for:
   - Retrofit interface method signatures match expected request/response types.
   - Response model fields align with `@SerializedName` / `@Json` annotations.
   - No breaking changes to public API surface consumed by other modules.
   - Nullable vs non-nullable types on response model fields (prefer nullable for network responses).
   - Error response handling present (not just happy path).

### Step 3: Network safety
4. Check for network-layer safety:
   - Timeout configuration present on HTTP clients.
   - TLS/certificate validation not disabled (no `trustAllCerts` or similar).
   - No hardcoded URLs that should be in BuildConfig or environment configuration.
   - No sensitive data (API keys, tokens) in source code -- should come from BuildConfig or secure storage.
   - Retry/backoff logic present for transient failures where appropriate.

### Step 4: Serialization
5. Check serialization safety:
   - Data classes used for request/response models (not regular classes).
   - Default values provided for optional fields.
   - Enum deserialization handles unknown values gracefully.
   - No mutable collections in response models.

### Step 5: Focused tests
6. Run focused tests for changed API areas:
   - Use the repo's focused test command (e.g. Android: `./gradlew :app:testDebugUnitTest --tests "*<ChangedApiClass>Test*"`).
   - If no specific tests exist, flag as a test coverage gap.

## Output format
```
## API Validation Results
### Changed API files
- [file list]

### Contract consistency
| Check | Status | Details |
|-------|--------|---------|
| Method signatures | pass/warn/fail | ... |
| Response models | pass/warn/fail | ... |
| Breaking changes | pass/warn/fail | ... |
| Nullability | pass/warn | ... |
| Error handling | pass/warn/fail | ... |

### Network safety
| Check | Status | Details |
|-------|--------|---------|
| Timeouts | pass/warn | ... |
| TLS validation | pass/fail | ... |
| Hardcoded URLs | pass/warn | ... |
| Secrets in source | pass/fail | ... |

### Serialization
| Check | Status | Details |
|-------|--------|---------|
| Data classes | pass/warn | ... |
| Default values | pass/warn | ... |
| Enum handling | pass/warn | ... |

### Focused tests
- Status: PASS / FAIL / SKIPPED (no tests found)

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2 (iterative development), failures are reported and accumulated but do not block commits. They become blocking at Phase 3 finalization.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Do not run the full test suite. Only run focused tests for changed API classes.
- Flag missing tests as warnings, not failures -- the developer may be adding them later.
- Hardcoded secrets in source code are always a `fail`, not a warning.
- TLS validation disabled is always a `fail`.
