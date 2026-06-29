# First Live MVP Acceptance Criteria

## Intake and routing

- A 100-document batch uploads and each document progresses independently.
- PDF, JPEG, PNG, and TIFF are safely detected by content.
- Password-protected, corrupt, oversized, and unsupported files fail with actionable status.
- Unknown structured XML/JSON is quarantined and never blindly routed to a visual model.
- Every attempt records route, format profile/version, schema, provider/parser, prompt, region pack, and processing region.

## Canonical data

- Every candidate validates against Canonical Invoice v2.
- Money is transported as decimal strings and correctly handles 0-, 2-, and 3-minor-unit currencies.
- Party identifiers and tax components are generic arrays; no India-only field is required.
- Ambiguous dates/currencies remain null and produce high-risk uncertainty.
- High-risk fields have evidence.

## Validation and acceptance

- Header, payable, tax-breakdown, and line arithmetic tests pass.
- No unresolved critical/high finding auto-accepts.
- Unsupported or experimental language/region profiles require review.
- Duplicate candidates are flagged before export.
- Approved revisions are immutable.

## Review and export

- An operator completes a 50-document batch without leaving the application.
- Generic JSON, normalized CSV ZIP, and XLSX export only approved revisions.
- Export row counts/checksums reconcile with approved documents.
- CSV/XLSX formula injection tests pass.

## Security and operations

- Cross-tenant access tests fail closed.
- Logs and exceptions contain no invoice text, identifiers, names, addresses, or canonical payloads.
- Immediate delete and retention purge remove all source, derivative, and export objects; verifier detects leftovers.
- Backup restore and failed-job recovery drills pass.
- Provider/region fallback cannot change without tenant approval.

## Pilot gates

- Auto-accepted high-risk precision ≥ 99.5%.
- Zero escaped critical monetary errors.
- Core header exact match ≥ 97% on clean English digital PDFs and ≥ 92% on complete mixed English holdout.
- At least 50% batch-time reduction for a qualifying pilot workflow.
