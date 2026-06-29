# Evaluation and Test Plan

## Objective

Prove that a named capability profile is accurate, safe, fast, and economically useful. A global average is not sufficient; metrics must be sliced by route, format, language, country, currency, document type, and quality.

## Dataset structure

### Required dimensions

- split: train/tuning, validation, frozen holdout
- vendor/supplier group
- buyer/customer group
- source family/profile/version
- visual quality: clean, scan, photo, skewed, blurred, low contrast
- document type
- country/jurisdiction candidates
- language and script
- currency and minor-unit class: 0, 2, 3, high-precision unit price
- tax regime family: VAT, GST, sales tax, withholding, no tax, mixed
- pages and line-item count
- digital text availability
- structured payload availability
- duplicate/credit-note/allowance/charge edge cases
- permission and ground-truth review status

### Split policy

- Split by vendor/template, not random page.
- Hold out entire vendors and at least one country/format combination.
- Never tune prompts or rules against the frozen holdout.
- Keep structured and visual representations of the same invoice in the same split.
- Record annotator disagreements as ambiguity rather than forcing false ground truth.

## First live MVP dataset target

Minimum recommended before launch:

- 200–300 total permissioned documents.
- 100 double-reviewed frozen holdout documents.
- At least 20 clean digital PDFs, 20 scans/photos, 10 credit/debit notes, and 10 multi-page documents.
- At least four currencies, including one 0-minor-unit and one 3-minor-unit currency.
- At least three supplier-country groups.
- English primary; any non-English profile reported separately and forced to review.
- At least 30 documents with line items if line extraction is in the pilot contract.

This is a launch minimum, not evidence for broad global support.

## Ground truth

- Annotate against Canonical Invoice v2.
- Two reviewers independently label high-risk header/tax/payable fields.
- Resolve disagreement with an adjudicator or mark `AMBIGUOUS`.
- Store ground truth separately from production data and under its own retention/permission terms.
- Record raw source value and normalized value for ambiguous date/number formats.

## Metrics

### Extraction

- exact match by field
- normalized exact match by field
- decimal absolute error
- line-item row precision/recall and alignment accuracy
- identifier scheme/value accuracy
- tax-breakdown component/rate/amount accuracy
- evidence locator coverage and correctness
- document-type accuracy
- currency/language/country detection accuracy

### Safety

- auto-accepted high-risk precision
- critical/high finding recall
- escaped critical monetary errors
- duplicate detection precision/recall
- visual/structured conflict detection
- schema-invalid output rate
- unsupported-format quarantine correctness

### Workflow

- median and p90 review time
- documents needing no correction
- fields corrected per document
- batch completion time versus baseline
- approval/rejection navigation errors

### Reliability and cost

- p50/p95 route latency
- queue delay
- provider/parser failure and retry rate
- cost per successful document/page
- repair rate
- orphan/deletion verifier failures

## Capability profile report

Every benchmark report identifies:

- schema version
- prompt hash/version
- model/provider/deployment
- parser and official validation artefact versions
- format registry version
- region pack/version
- currency registry date
- dataset manifest hash
- code commit
- date and operator

## Release gates

### `global_generic_v1`

- Core clean-digital header exact match ≥ 97%.
- Complete mixed-quality English holdout ≥ 92% for core header fields.
- Auto-accepted high-risk precision ≥ 99.5%.
- Critical monetary inconsistency recall = 100% on designed tests and holdout cases.
- Zero escaped critical monetary error during supervised pilot.
- Currency minor-unit and ambiguous-date tests all pass.

### Regional pack

In addition to generic gates:

- identifier validator tests pass;
- tax component/category mapping meets profile field gate;
- mandatory-field findings have required recall;
- at least the minimum country/vendor diversity in the profile manifest;
- unsupported local scenarios are documented and forced to review.

### Structured adapter

- exact profile/version detection;
- official schema/business-rule validator results captured where available;
- deterministic mapping regression fixtures pass;
- credit-note and allowances/charges cases pass;
- hybrid visual/structured conflict tests pass.

## Regression protocol

Any change to prompt, provider, model, parser, schema, format registry, currency registry, rule pack, or normalization code requires:

1. unit/contract tests;
2. validation-set run;
3. frozen-holdout run;
4. comparison against current champion;
5. explicit approval when any safety metric regresses;
6. version bump and rollback path.

Do not ship solely because aggregate accuracy improved. A regression in payable amount, invoice number, currency, or duplicate safety can block release.

## Adversarial tests

- printed prompt-injection instructions
- misleading “total” labels
- multiple invoice/reference dates
- decimal comma versus thousands separator
- ambiguous currency symbol `$`
- zero/three-decimal currencies
- negative credit note and partial credit
- tax-inclusive versus tax-exclusive line prices
- withholding and prepaid amounts
- repeated headers across pages
- rotated/low-resolution images
- malicious XML entities/deep nesting
- spreadsheet formula text in descriptions
- conflicting PDF and embedded XML values
