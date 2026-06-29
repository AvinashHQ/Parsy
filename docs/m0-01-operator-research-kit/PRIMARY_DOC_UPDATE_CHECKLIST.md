# Primary Document Update Checklist

Do not rewrite the Product Brief or Business Validation document after every interview. Maintain interview records separately, then update the primary docs once the first synthesis is complete.

## `docs/01_PRODUCT_BRIEF.md`

Update or confirm:

- Initial customer profile using observed roles, volumes and workflow.
- Exact workflow boundary for the first live MVP.
- Whether header-only, line-item or both are required.
- Required input formats and operational language.
- Required first export type and columns.
- Review responsibility and unacceptable errors.
- Baseline metric and target time saving.
- Document scenarios explicitly excluded from the first pilot.
- Evidence required for operator approval.

Add a dated evidence note:

- interview count;
- organizations represented;
- observation count;
- baseline median/range;
- source synthesis report version.

## `docs/09_BUSINESS_VALIDATION.md`

Update:

- Discovery evidence summary.
- Baseline workflow and measured bottlenecks.
- Error-category ranking.
- Which validation hypotheses were confirmed/rejected/unknown.
- Whether reviewed export-only output is valuable.
- Candidate pilot teams and willingness signals.
- Security/retention/residency constraints.
- Commercial value unit: document, batch, operator hour or client account.
- Most demanded future regional or ERP capability.

## Changes that must become separate issues

Create a separate issue rather than silently editing contracts when interviews imply:

- a new canonical field;
- a change to `canonical_invoice_v2` semantics;
- a new region profile;
- a new input format;
- a new ERP adapter;
- a retention/security architecture change;
- a direct-posting requirement.
