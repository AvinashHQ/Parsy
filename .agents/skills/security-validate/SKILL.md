---
name: security-validate
description: Check for secrets, vulnerable dependencies, and security anti-patterns in changed code
metadata:
  audience: engineers
  scope: iterative-validation
---
# Security Validate

## When to use
Triggered automatically by `smart-validate` when dependency files, auth code, or security-sensitive code changes. Also triggered manually via `/validate-security`.

## Trigger patterns (Android-shaped examples — the repo's smart-validate routing/overlay is authoritative)
```
**/build.gradle.kts, **/settings.gradle.kts, **/gradle.properties
**/libs.versions.toml, gradle/libs.versions.toml
**/*.kt (under auth/, security/, middleware/, crypto/)
**/keystore.properties, **/*.jks, **/*.keystore
Platform permission manifests (AndroidManifest.xml, entitlements, CSP configs)
```

## Workflow

### Step 1: Secret scanning
1. Scan the diff for hardcoded secrets using these patterns:
   - API keys: strings matching `[A-Za-z0-9_-]{20,}` in assignment context.
   - Tokens: `Bearer `, `token = "`, `apiKey = "`, `secret = "`.
   - Passwords: `password = "`, `passwd`, `pwd` in non-test code.
   - Private keys: `-----BEGIN`, `PRIVATE KEY`.
   - Firebase/Google: `AIza`, `ya29.`, `GOCSPX-`.
   - Generic: `sk_live_`, `pk_live_`, `ghp_`, `gho_`.
2. Check that `.gitignore` covers sensitive file patterns (`.env`, `*.jks`, `keystore.properties`, `google-services.json`).
3. Verify no credential files are being committed.

### Step 2: Dependency audit
4. If dependency files changed (`build.gradle.kts`, `libs.versions.toml`):
   - Check for known vulnerable dependency versions (cross-reference with recent CVE databases if accessible).
   - Flag dependencies pinned to old major versions when newer versions exist.
   - Check for dependencies from untrusted sources.
   - Verify no dependencies were added with `implementation` that should be `testImplementation`.

### Step 3: Permission audit
5. If a platform permission manifest changed:
   - List all permission additions/removals.
   - Flag dangerous permissions added without clear justification.
   - Check for `android:exported="true"` on new components without intent filters.
   - Check for `android:usesCleartextTraffic="true"`.

### Step 4: Code security patterns
6. Scan changed source files for security anti-patterns:
   - Sensitive data in `Log.*()` calls (prefer `AppLog` which sanitizes).
   - `SharedPreferences` storing sensitive data in MODE_PRIVATE without encryption.
   - WebView with JavaScript enabled and `addJavascriptInterface` (XSS risk).
   - Intent data not validated from external sources.
   - SQL injection via string concatenation in queries.
   - Disabled TLS certificate validation (`X509TrustManager` that trusts all).

### Step 5: Signing and release safety
7. If signing or release configuration changed:
   - Verify signing config reads from `keystore.properties` or injected properties, never hardcoded.
   - Check that release build types have `minifyEnabled` and `proguardFiles` configured.
   - Verify debug signing is not used for release variants.

## Output format
```
## Security Validation Results
### Changed files
- [file list]

### Secret scanning
| Check | Status | Details |
|-------|--------|---------|
| Hardcoded secrets | pass/fail | ... |
| Credential files | pass/fail | ... |
| Gitignore coverage | pass/warn | ... |

### Dependency audit
| Check | Status | Details |
|-------|--------|---------|
| Known vulnerabilities | pass/warn/fail | ... |
| Untrusted sources | pass/fail | ... |
| Scope correctness | pass/warn | ... |

### Permission audit
| Check | Status | Details |
|-------|--------|---------|
| Dangerous permissions | pass/warn/fail | ... |
| Exported components | pass/warn | ... |
| Cleartext traffic | pass/fail | ... |

### Code patterns
| Check | Status | Details |
|-------|--------|---------|
| Sensitive logging | pass/warn/fail | ... |
| Data storage | pass/warn | ... |
| Input validation | pass/warn | ... |
| TLS validation | pass/fail | ... |

### Verdict: PASS / WARN / FAIL
```

## Advisory behavior
During Phase 2, failures are reported and accumulated. At Phase 3, all security failures are blocking.

**Exception**: Hardcoded secrets and disabled TLS validation are always immediate failures regardless of phase. These should be fixed before committing.

## Guardrails
- This is a read-only analysis skill. Do not modify files.
- Secrets in source code are always a `fail`. No exceptions.
- Disabled TLS validation is always a `fail` unless explicitly in a test/debug-only path.
- Do not flag test fixtures that use dummy API keys or passwords (e.g., `"test-api-key"` in test code).
- Do not modify signing files, Google services JSON, or production secrets.
- When in doubt about a potential secret, flag as `warn` rather than ignoring.
