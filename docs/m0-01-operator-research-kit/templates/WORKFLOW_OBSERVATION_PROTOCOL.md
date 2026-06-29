# Workflow Observation and Timing Protocol

## Purpose

Create a baseline that can later be compared with the MVP without changing the measurement definition.

## Observation unit

Prefer a completed batch. When unavailable, observe one representative document and record that the sample is document-level.

Capture:

- participant ID;
- organization ID;
- observation ID;
- date;
- measurement method;
- document count;
- total pages;
- header-only or line-item workflow;
- source types;
- currencies/countries/languages;
- workflow start and end boundary.

## Timing boundaries

Default start:

> The operator begins handling documents that have arrived and are available to process.

Default end:

> The reviewed data is ready for import/posting or has been successfully imported when import preparation is part of the selected workflow.

Do not include supplier payment execution unless it is explicitly part of the targeted MVP workflow.

## Time categories

### Active touch time

Time spent actively reading, typing, checking, calculating, communicating, correcting or preparing output.

### System wait time

Time waiting for downloads, uploads, imports, page rendering or software responses while the operator cannot progress.

### External wait time

Time waiting for another person, supplier or client. Record duration separately; do not normalize it as operator touch time.

### Rework time

Active time spent correcting an earlier entry or resolving an exception.

## Stage timing table

Use stages from `reference/WORKFLOW_STAGE_TAXONOMY.md`. Record one row per stage occurrence, not only one total per interview.

Required fields:

- stage;
- active seconds;
- system-wait seconds;
- rework seconds;
- documents affected;
- tool;
- handoff role;
- notes.

## Normalization

Calculate:

- active minutes/document;
- rework minutes/document;
- system-wait minutes/document;
- documents/operator hour;
- errors/100 documents.

Segment line-item workflows separately from header-only workflows.

## Timing safeguards

- Do not silently remove interruptions; label them.
- Do not count the interviewer's questions as workflow time.
- Do not extrapolate one unusually easy document to the monthly volume without noting the limitation.
- Keep observed and estimated measurements separate.
- Record whether the participant knew they were being timed.
