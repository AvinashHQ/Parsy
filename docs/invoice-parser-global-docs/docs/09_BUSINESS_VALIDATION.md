# Business Validation and Positioning

## Positioning

Avoid:

- “Understands every invoice like a human.”
- “Works in every country.”
- “Fully tax compliant.”
- “Zero retention” without contractual and provider evidence.

Use:

> Turn mixed supplier invoices into normalized, evidence-backed accounting data. The system verifies arithmetic, flags ambiguity, and lets your team review exceptions before export. Regional tax and ERP capabilities are enabled only when separately tested.

## Initial wedge

Do not sell “global invoice infrastructure” first. Sell one measurable workflow:

> Batch invoice intake to reviewed CSV/XLSX for outsourced accounting and AP teams that receive many supplier layouts and currencies.

A global-ready architecture prevents rework, while the commercial wedge remains narrow.

## Pilot offer

- 50–100 difficult documents for the first benchmark; 500+ during live test.
- Agreed fields and export template before processing.
- Customer provides permission and corrected ground truth.
- Supervised human approval; no direct posting or tax advice.
- Results include accuracy by profile, exception list, review time, cost, and estimated time saved.
- Explicit processors, regions, retention, and deletion terms.
- Experimental languages/formats are clearly labelled.

## Discovery questions

### Workflow

1. Which accounting/AP step are we replacing or accelerating?
2. Monthly documents, pages, and peak batch size?
3. Header-only or line items?
4. What import template or system is used?
5. Who reviews, and what is current time per document?

### Global variability

6. Supplier/buyer countries?
7. Languages and scripts?
8. Currencies and tax regimes?
9. Visual PDF/image versus structured XML/hybrid documents?
10. Which identifiers and references matter operationally?
11. How are credit notes, withholding, freight, and prepaid amounts handled?

### Risk

12. Which error is financially unacceptable?
13. Does every result require human approval?
14. Residency, processor, and retention restrictions?
15. Can documents be used for evaluation after the pilot, and for how long?

### Commercial

16. Is value measured per document, operator hour, batch, or client account?
17. Would the team pay for reviewed exports without direct ERP posting?
18. Which single regional or ERP adapter would unlock payment?

## Validation hypotheses

- H1: review time, not raw extraction accuracy, is the dominant adoption metric.
- H2: generic normalized exports create value before direct integrations.
- H3: arithmetic/evidence warnings materially improve operator trust.
- H4: the first paid expansion will be one regional pack or ERP mapping, not broad global coverage.
- H5: customers will accept short retention when deletion is explicit and verifiable.

## Pricing hypotheses

Test:

- fixed supervised pilot fee;
- per successfully reviewed document;
- monthly volume tier with included operators;
- setup fee for a tested export mapping.

Do not price by model token or claim a stable per-invoice margin before real page, repair, and review distributions are measured.

## Go/no-go

Continue only when:

- at least one workflow saves ≥50% time with repeatable quality;
- safety gates hold;
- operators prefer the review flow to manual entry;
- cost plus support leaves room for a viable price;
- at least one customer asks to continue or pay;
- the next regional/integration milestone is clearly demanded.

## Defensibility

- permissioned multiregion evaluation data;
- canonical mapping and correction history;
- profile-specific acceptance metrics;
- versioned regional rules and structured adapters;
- tested export mappings;
- faster review UX and operational trust.
