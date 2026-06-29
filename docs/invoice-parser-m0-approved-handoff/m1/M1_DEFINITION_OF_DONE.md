# M1 Definition of Done

## M1-01 Canonical Invoice v2

- value objects map one-to-one to the approved JSON Schema;
- unknown fields and version mismatch behavior are explicit;
- valid/invalid contract fixtures pass;
- no country-specific core columns or classes.

## M1-02 Decimal and currency precision

- money uses decimal strings/decimal values, never float;
- currency registry supports zero, two and three minor units;
- tolerance behavior is named and tested;
- USD, JPY and KWD fixtures pass.

## M1-03 Generic domain structures

- parties and identifiers are typed collections;
- addresses preserve source values and normalized country codes separately;
- taxes support type, component, jurisdiction, category, rate, base, amount and payable effect;
- classifications and references are generic;
- line items support allowances, charges and tax breakdowns.

## M1-04 Universal validation

- schema, required-field, arithmetic, evidence and date/currency findings have stable codes;
- severity is separate from UI behavior;
- all critical conditions in the pilot policy are represented;
- tax rules validate arithmetic, not legal compliance.

## M1-05 Duplicate fingerprint

- tenant-scoped normalized keys;
- supplier identity, invoice number, date/currency/amount inputs documented;
- formatting differences normalize consistently;
- false-positive escape path represented as a finding/confirmation need.

## M1-06 Exports

- JSON round-trip is stable;
- CSV bundle and workbook reconcile to the canonical document;
- all exports include version and review status;
- formula injection is neutralized;
- unapproved revisions cannot be exported through the domain service.

## M1-07 Migration policy

- schema version rules documented;
- compatible minor migrations deterministic;
- incompatible major versions rejected unless an explicit migrator exists;
- migration fixtures and rollback behavior pass.

## Milestone gate

The M1 demonstration runs offline with no model provider and produces a deterministic report for all fixtures.
