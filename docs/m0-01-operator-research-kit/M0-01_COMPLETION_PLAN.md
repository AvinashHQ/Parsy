# M0-01 Completion Plan — Interview Operators and Baseline Workflow

## 1. Research questions

The interviews must resolve the following decisions:

1. Which exact workflow should the first MVP accelerate?
2. Where does operator touch time occur?
3. Which fields and document types cause the most rework?
4. Which mistakes are financially or operationally unacceptable?
5. What evidence does an operator need before approving an extracted value?
6. Is reviewed CSV/XLSX useful without direct ERP posting?
7. What countries, currencies, languages, file types and tax patterns appear in the initial cohort?
8. Which downstream template or accounting system determines the required output?
9. What retention, residency and document-sharing restrictions affect a pilot?
10. What measurable result would cause a team to continue or pay?

## 2. Participant mix

Recruit people who personally perform or supervise the workflow. Do not substitute software vendors, consultants without recent hands-on work, or general business owners who cannot describe the process at field level.

Recommended five-person minimum:

| Slot | Preferred profile | Reason |
|---|---|---|
| 1 | Bookkeeper/junior accountant | High-frequency data-entry perspective |
| 2 | AP clerk/accounting operator | In-house approval and exception workflow |
| 3 | Senior accountant/reviewer | Error, audit and approval perspective |
| 4 | Outsourced accounting team lead | Batch operations and client variability |
| 5 | Firm owner/operations manager who still knows the workflow | Commercial value and adoption constraints |

Diversity targets:

- At least three organizations.
- At least one organization receiving documents from multiple countries or currencies.
- At least one spreadsheet/CSV import workflow.
- At least one workflow involving line-item entry.
- Prefer monthly volume above 500 documents, but include one smaller team only when its workflow is unusually relevant.

## 3. Recruitment sequence

1. Build a candidate list of 15–20 people.
2. Send a short, non-sales discovery request.
3. Screen for direct workflow involvement, volume, document variability and willingness to demonstrate the process.
4. Schedule 45 minutes; reserve 60 minutes for live observation.
5. Confirm that no source document needs to be emailed or uploaded for this issue.
6. Obtain explicit permission before recording audio, video or screens.
7. Stop recruitment only after five qualifying interviews are complete, not merely booked.

Expected funnel:

- 15–20 candidates contacted.
- 8–10 responses.
- 6–7 scheduled.
- At least five completed and usable.

## 4. Interview execution

Each session has four phases:

### A. Context — 5 minutes

Capture role, team, monthly volume, document types, countries, currencies, languages and downstream systems.

### B. Workflow reconstruction — 15 minutes

Start from document arrival and continue through final import/entry, review, correction, posting preparation and archival. Record handoffs, tools and waiting points.

### C. Timed walkthrough — 15 minutes

Preferred: observe a recent or representative document/batch using permissioned or redacted material.

Record:

- touch time by workflow stage;
- elapsed time separately;
- document count and page count;
- number of exceptions;
- fields manually entered or checked;
- corrections and their causes;
- interruptions or system delays.

When direct observation is impossible, reconstruct the last completed batch using timestamps, batch records, operator notes or a structured estimate. Mark the measurement method explicitly.

### D. Risk and value — 10 minutes

Ask which errors are unacceptable, which evidence is needed, whether export-only output is useful, and what outcome would justify continued use or payment.

## 5. Baseline measurement rules

### Primary measure: operator touch time

Touch time is active human work attributable to the invoice workflow. It excludes unattended uploads, queue waits and overnight delays.

Record both:

- batch touch minutes; and
- normalized touch minutes per document.

Formula:

`touch minutes per document = total active touch minutes / documents completed`

### Secondary measures

- elapsed batch time;
- documents per operator hour;
- first-pass completion rate;
- correction count per 100 documents;
- critical/high error count;
- percentage requiring another person;
- percentage requiring supplier/client clarification;
- line-item entry share;
- duplicate-check time;
- import/export preparation time.

### Measurement quality

Use one of these labels:

1. `OBSERVED` — timed during a live walkthrough.
2. `SYSTEM_SUPPORTED` — reconstructed from system/batch timestamps and records.
3. `RECENT_RECALL` — based on a recent named batch.
4. `GENERAL_ESTIMATE` — operator’s broad estimate.

Do not combine these methods without preserving the label. Prefer observed and system-supported evidence when calculating the final baseline.

## 6. Error capture

Record errors as events, not vague complaints. Each event needs:

- workflow stage;
- field or output affected;
- error category;
- severity;
- how it was detected;
- time to correct;
- downstream impact;
- whether automation may prevent, detect or worsen it.

Use `reference/ERROR_TAXONOMY.md` to keep interviews comparable.

## 7. Analysis and synthesis

After each interview:

1. Complete the interview record within 24 hours.
2. Enter timing rows and error events in the workbook.
3. Mark assumptions and unanswered questions.
4. Write three strongest observations and one disconfirming observation.
5. Update the candidate hypothesis list.

After five interviews:

1. Calculate median and range for touch minutes per document.
2. Segment by header-only versus line-item workflow.
3. Rank error categories by frequency, severity and correction time.
4. Identify common required fields and output columns.
5. Identify unsupported or high-risk document scenarios.
6. Decide the first pilot workflow and target operator.
7. Document which product assumptions were confirmed, rejected or remain unknown.
8. Propose updates to the Product Brief and Business Validation documents.

## 8. Issue artifacts

Required evidence attached or linked from the issue:

- Candidate/recruiting tracker.
- Five completed interview records with anonymized participant IDs.
- Timing baseline rows for all five interviews.
- Error-event records or an explicit “none observed” entry.
- Synthesis report.
- Product Brief and Business Validation change list.
- Privacy review note.

Do not attach raw customer invoice images to the issue.

## 9. Definition of done

The issue may be closed only when all conditions are true:

- [ ] Five qualifying interviews are completed.
- [ ] Participant roles and organizations meet the minimum diversity threshold, or the exception is documented.
- [ ] Each interview has workflow stages, tools, handoffs and output recorded.
- [ ] Each interview has touch minutes per document with measurement method.
- [ ] Error categories and severity are recorded.
- [ ] At least two workflows were directly observed, or the shortfall and mitigation are documented.
- [ ] The first target workflow is stated in one sentence.
- [ ] Required fields and first export format are listed.
- [ ] Unacceptable error categories are listed.
- [ ] Pilot privacy constraints are listed.
- [ ] `01_PRODUCT_BRIEF` and `09_BUSINESS_VALIDATION` updates are drafted.
- [ ] The implementation-checklist interpretation below is recorded.

## 10. Implementation-checklist interpretation

This is a discovery issue, so the standard implementation checklist applies as follows:

### Test/fixture reference identified

Use anonymized interview IDs (`INT-001` through `INT-005+`), baseline observation IDs and error-event IDs as the research fixtures. Raw invoices are not issue fixtures.

### Affected schema/profile version recorded

Record `discovery input for canonical_invoice_v2 / global_generic_v1`. This issue does not itself change either version. Any recommended contract change becomes a separate issue and ADR.

### Privacy/logging impact reviewed

Record:

- consent status;
- recording status;
- note storage location;
- retention date;
- whether source documents were viewed;
- whether any personal or financial data was copied.

No source content should appear in issue comments, analytics, application logs or the shared tracker.

### Observability signal defined

Research signals are:

- interviews completed;
- qualifying organizations represented;
- observed workflows completed;
- percentage of interviews with usable timing;
- baseline minutes per document;
- error events per 100 documents;
- top error categories;
- percentage willing to pilot reviewed export;
- percentage willing to provide permissioned documents later.

### Rollback or feature-flag plan

`Not applicable — no production behavior changes.` Any product-scope decision resulting from this issue must be reversible until M0 scope freeze.
