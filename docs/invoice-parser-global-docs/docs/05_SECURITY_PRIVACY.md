# Security, Privacy, and Global Launch Controls

This document is an engineering and operational baseline, not legal advice or a claim of compliance with every privacy law.

## Data roles

For a typical B2B pilot:

- The accounting firm/customer decides why documents are processed and is normally the controller/business.
- The product processes documents on customer instructions and is normally the processor/service provider.
- Model, hosting, storage, email, and monitoring vendors may be subprocessors.

The contract and actual data flow must confirm these roles for each launch region.

## Data inventory

Potentially sensitive content includes:

- names, addresses, phone/email details;
- tax/business identifiers;
- bank/payment instructions;
- employee/customer expense details;
- signatures and handwritten notes;
- product/service descriptions and prices;
- invoice references that reveal commercial relationships.

Treat every source and derived canonical record as confidential customer data even when it may not be personal data.

## Global launch gate

Before accepting a pilot in a new country or hosting region, record:

1. customer and product legal entities;
2. controller/processor roles;
3. applicable contract/DPA;
4. data categories and purpose;
5. subprocessors and their locations;
6. chosen hosting/object-storage/model processing regions;
7. cross-border transfer mechanism or customer approval where required;
8. retention and deletion schedule;
9. data-subject/customer request process;
10. breach contact and notification workflow;
11. whether data residency is contractual;
12. whether any regulated data class is prohibited.

Do not market “GDPR compliant,” “DPDP compliant,” or similar without legal review and implemented evidence.

## Data minimization

- Do not retain full OCR/document text as a convenience cache.
- Store only canonical fields required by the agreed output and limited evidence snippets.
- Disable optional payment/account extraction unless the pilot needs it.
- Mask full bank account/IBAN values by default; the MVP does not execute payments.
- Do not collect government IDs unrelated to invoice processing.
- Do not use pilot documents for model training without separate explicit written permission.

## Retention

Pilot default:

- raw source and embedded structured payload: delete after approved export or within 24 hours;
- thumbnails/previews: same deadline as source;
- generated exports: delete within 7 days;
- canonical records and audit metadata: customer-configured short period, preferably no longer than required to evaluate the pilot;
- content-free operational metrics: may be retained longer under documented policy.

Immediate delete must enqueue purge and make the batch unavailable. A verifier independently checks database, object storage, derived blobs, exports, and failed multipart uploads.

## Provider policy

For every model/parser provider, maintain:

- service and deployment name;
- processing region;
- retention/abuse-monitoring behavior;
- training-use terms;
- subprocessor list;
- encryption and access controls;
- contractual zero-retention option, if any;
- approved document categories;
- date of last review.

Never claim zero retention solely because the application deletes its own copy.

## Residency and transfers

- Tenant configuration declares the approved hosting and model-processing regions.
- Documents must not be routed to another region/provider as an automatic outage fallback.
- EU/UK and other cross-border requirements must be assessed before launch; the architecture preserves processor/region metadata per attempt.
- A regional deployment is an operational choice, not merely a UI preference.

## Authentication and tenant isolation

- Invite-only accounts for MVP.
- Rails authentication generator or equivalent audited implementation.
- Secure, HttpOnly, SameSite cookies and forced TLS.
- Tenant scope applied at every query and storage path.
- Authorization tests must attempt cross-tenant batch, blob, export, and API access.
- Admin actions are audited.
- MFA should be enabled before unsupervised customer use.

## Upload security

- Validate MIME, magic bytes, extension, size, page count, archive entry count, and decompressed size.
- Quarantine unsupported XML/JSON; disable external entity resolution and network fetches.
- Reject encrypted/password-protected files with guidance.
- Use bounded PDF/image processing time and memory.
- Strip or avoid executing embedded scripts/actions.
- Consider malware scanning before broader public intake.

## Structured document security

- Parse XML with DTD/external entity/network access disabled.
- Bound element count, nesting depth, text size, and attachment size.
- Never execute macros or embedded files.
- Treat PDF embedded XML as untrusted input.
- Official validators and schemas are version-pinned and checksum-verified.

## Logging and telemetry

Allowed:

- internal IDs, pseudonymous tenant ID;
- route/profile/version;
- language/country/currency codes;
- finding/error codes;
- timings, queue state, page count, token/cost metrics.

Forbidden:

- document images/text;
- evidence snippets;
- party names and addresses;
- invoice numbers;
- full tax/business/bank identifiers;
- canonical or provider response bodies;
- signed blob URLs and secrets.

Use automated logging tests with seeded sensitive values.

## Encryption and secrets

- TLS in transit.
- Storage/database encryption at rest.
- Secrets injected from a secrets manager or deployment secret store.
- Separate least-privilege credentials for web, job, backups, and CI where practical.
- Rotate model/storage/database credentials on personnel change or suspected exposure.
- Encrypted backups with tested restore and documented retention.

## Threats to test

- cross-tenant IDOR;
- prompt injection printed in an invoice;
- XML external entity and entity-expansion attacks;
- decompression/image bombs;
- malicious filename/content-type mismatch;
- model response containing unexpected content;
- signed URL leakage;
- background-job argument leakage;
- deletion race and orphaned blob;
- provider outage causing unapproved fallback;
- spreadsheet formula injection in CSV/XLSX exports.

Exporters must neutralize cell values beginning with `=`, `+`, `-`, or `@` when they originate from untrusted text and the target format interprets formulas.

## Incident response minimum

1. Stop intake and revoke affected sessions/credentials.
2. Preserve content-free system evidence and access logs.
3. Identify tenants, processors, regions, and time window.
4. Disable affected provider/profile/adapter through feature flag.
5. Notify the internal incident owner and customer contacts according to contracts/law.
6. Rotate credentials and remediate.
7. Verify deletion/containment.
8. Complete root-cause analysis and regression tests.

## Pre-live checklist

- DPA/pilot agreement signed.
- Approved subprocessor list and regions recorded.
- Tenant isolation tests pass.
- Upload abuse tests pass.
- Logs verified content-free.
- Deletion and orphan reconciliation pass.
- Backup restore drill passes.
- No unapproved fallback processor.
- Retention statements match implementation.
- Privacy/security claims reviewed and evidence-linked.
