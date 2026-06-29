# Documentation and Contract Validation Report

**Review date:** 28 June 2026  
**Package:** Global AI Invoice Parser — Rails Documentation Pack

## Review conclusion

The package is internally consistent for a documentation-first implementation kickoff. The previous India-first assumptions have been removed from the canonical core. India GST and Tally remain optional examples behind a versioned capability profile.

The package is **global-ready, not globally certified**. It can represent and route invoices from different countries and currencies, while production support for a language, regional tax regime, structured syntax, or ERP adapter remains independently gated.

## Automated checks completed

- All JSON files parse successfully.
- Canonical EUR and JPY sample documents validate against Canonical Invoice Schema v2.
- All example region profiles validate against the region-profile schema.
- OpenAPI and reference YAML files parse successfully.
- CSV assets have consistent column counts.
- The HTML blueprint parses and contains the global scope and milestone sections.
- The workbook formula scan found no spreadsheet errors.
- The documentation archive contains no generated Rails application, model, controller, migration, Docker, or test boilerplate.

## Cross-document consistency checks

- `docs/08_DELIVERY_PLAN.md`, `planning/mvp_issues.csv`, and the workbook contain matching M0–M6 milestones.
- M0–M4 are launch blockers; M5 is the closed pilot; M6 is post-MVP regional or structured expansion.
- The issue backlog contains 51 implementation issues with owner role, primary documentation, acceptance criteria, and dependencies.
- The canonical schema, field dictionary, validation rules, SQL reference, prompts, samples, and export templates use generic identifiers and tax-breakdown arrays.
- Generic JSON, CSV, and XLSX are core exports. Region- or ERP-specific exports are optional adapters.

## Known limitations requiring implementation evidence

1. Model accuracy has not yet been measured on a permissioned live corpus.
2. Currency minor-unit data must be maintained from an authoritative, versioned source.
3. Structured adapters are detection-first until exact syntax/profile fixtures pass.
4. Non-English extraction may be explored but cannot auto-accept in the initial profile.
5. Regional tax semantics cannot be inferred merely from country detection.
6. Privacy, residency, processor, and transfer requirements must be approved for each pilot.
7. A full Rails implementation, deployment, security test, restore drill, and deletion drill remain milestone work rather than documentation claims.

## First implementation action

Start with M0. Do not generate a large Rails codebase before the pilot profile, required fields, unacceptable errors, corpus rights, retention plan, and export shape are frozen.
