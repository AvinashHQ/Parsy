# Pilot Security and Retention Decision

**Decision version:** `pilot_security_v1.0`  
**Evidence status:** internal assumed decision; external launch requires actual legal/security approval.

## Hosting and tenancy

- single EU hosting region for the initial pilot;
- tenant ID required on all business records and object keys;
- private object storage only;
- short-lived signed access URLs;
- encryption in transit and at rest;
- no public document URLs.

## Retention

| Data | Default retention |
|---|---|
| Source document | Delete after approved export or within 24 hours; hard cap 7 days from upload |
| Rendered pages/thumbnails | Same as source document |
| Generated exports | 7 days |
| Canonical/review metadata | 30 days after pilot batch closure unless contract requires shorter |
| Content-free operational logs | 30 days |
| Aggregated non-content metrics | May be retained |
| Evaluation corpus | Only under separate written permission and named retention |

## Processing requirements

- no invoice text, image bytes or extracted values in logs, exception payloads or job arguments;
- AI provider must offer paid no-training terms and documented retention behavior;
- provider, hosting, email and error-monitoring processors listed before live use;
- no search grounding or unrelated tools on customer content;
- purge-now endpoint plus orphan-object reconciliation;
- deletion verification event recorded without retaining content;
- backup retention must not silently exceed the agreed policy.

## Pilot legal boundary

- supervised export-only workflow;
- no tax, legal or accounting advice;
- customer confirms authorization to provide documents;
- customer owns approval and downstream posting;
- separate permission required for evaluation reuse.

## M1 impact

M1 domain objects must support tenant scope, retention timestamps, schema/profile versions and content-free identifiers. M1 itself does not connect to external processors.
