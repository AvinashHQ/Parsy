# Invoice Workflow Stage Taxonomy

Use these codes in every interview so timing can be aggregated.

| Code | Stage | Includes | Excludes |
|---|---|---|---|
| INTAKE | Receive and collect | Downloading, collecting attachments, scanning inbox/folder | Reading invoice fields |
| PREP | File preparation | Renaming, rotating, splitting, merging, grouping, assigning | Data entry |
| CLASSIFY | Document classification | Invoice/receipt/credit note/duplicate determination | Accounting coding |
| READ_HEADER | Header extraction | Supplier, number, dates, currency, references | Line items |
| READ_LINES | Line-item extraction | Description, quantity, price, line tax/classification | Header-only fields |
| LOOKUP | External lookup | Supplier master, tax ID, PO, exchange rate, cost centre | Pure data entry |
| VALIDATE | Verification | Arithmetic, totals, tax, duplicates, completeness | Reviewer handoff waiting |
| CODE | Accounting coding | Ledger, account, department, project, tax code | Source extraction |
| ENTER | System entry | Typing/pasting data into spreadsheet/accounting system | Import-file preparation |
| PREP_EXPORT | Export/import preparation | Column mapping, formatting, CSV/XLSX cleanup | System import execution |
| IMPORT | Import/posting preparation | Uploading file, resolving import errors | Final payment execution |
| REVIEW | Human review | Secondary check, approval, correction request | Waiting for reviewer |
| CLARIFY | Clarification work | Supplier/client questions and active follow-up | Passive external wait |
| ARCHIVE | Final organization | Filing source/output, naming, retention actions | Unrelated record management |
| REWORK | Correction | Re-entry or correction caused by earlier error | First-pass work |
| OTHER | Other active work | Necessary work not covered above | Unrelated interruptions |
