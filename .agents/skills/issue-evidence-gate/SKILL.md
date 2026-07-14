---
name: issue-evidence-gate
description: Pre-filing evidence gate for issue-filing routines and drafted issues. Extracts falsifiable claims from a drafted issue (spec/protocol codes, file:line, API/method names, feasibility assertions, metrics) and verifies each via a read-only Explore pass against HEAD, cited code, the repo's contract-validate discipline, and authoritative citations. Returns a per-claim VERIFIED/UNVERIFIED/REFUTED ledger and a PASS/PASS-WITH-LABEL/BLOCK decision. Read-only; never files issues or edits code.
metadata:
  audience: maintainers
  scope: issue-quality-gate
---
# Issue Evidence Gate

## When to use
Run on a **drafted** issue, AFTER dedup/anti-noise checks and immediately BEFORE `gh issue create`, to
prevent misleading or partially-correct issues from being filed. The repo's issue-filing routines
(per the routine standard) MUST run this gate; the human `/create-issue` (`github-issue`) path SHOULD run
it whenever the draft asserts protocol/spec codes, feasibility, specific `file:line`, or metrics (skip for
trivial issues).

Motivating failure (from AirMouse): a routine filed an issue asserting "Mic mute (HID Consumer Page 0x00B7
— Microphone)" and "No descriptor change needed." Both were false (`0x00B7` is the Consumer-page `Stop`
usage; a real mic-mute needs a Telephony-page descriptor change that forces re-pairing). Nothing verified
the claims against the code or the spec. This gate catches exactly that class of error.

## Operating mode (hard boundaries)
- **READ-ONLY.** Never edit code/config/docs, never open PRs, and **never call `gh issue create`** — the
  only output is a structured verdict returned to the caller, which then files (or doesn't).
- Run the verification in a **delegated read-only `Explore` pass** so verbose tool output stays out of the
  caller's context.
- **Bias:** absence of evidence ⇒ `UNVERIFIED` (downgrade, don't block); a positive contradiction ⇒
  `REFUTED` (block). Inherit `contract-validate`'s rule verbatim for protocol bytes: *"Do not guess byte
  sequences. If unsure, flag for manual review."*
- The gate governs **falsifiable facts**, not editorial judgment (priority, user value). It never blocks an
  issue for being low-value — only for asserting unverified or contradicted facts.

## Inputs (the caller passes a drafted issue)
- `title`, `body` (markdown).
- `claims[]` (optional) — assertions the routine already knows it is making (e.g. a research routine's
  feasibility bullets, a crash-triage routine's root-cause statements). The gate also auto-extracts from the body.
- `domain` hint — e.g. `protocol` / `crash` / `perf` / `architecture` / `analytics` / `ux` (routes verification).

## Workflow

### Step 1 — Extract falsifiable claims
Parse `title` + `body` + supplied `claims[]` into a typed list. Skip non-falsifiable prose (opinions,
prioritization). Bucket each claim:

| Type | Examples | Verified by |
|------|----------|-------------|
| `identifier` | a magic number, `Report ID 3`, a `file:line`, a constant name, a platform API method | Existence/location at HEAD (`git grep`/read). Protocol/spec numbers ALSO need an external citation (see `external-spec`). |
| `feasibility` | "no schema/descriptor change needed", "already supported", "no migration", "pure UI + plumbing" | Read the cited code + the governing contract. Contract claims routed through the repo's `contract-validate` checklist and authoritative in-repo contract docs. |
| `external-spec` | "Consumer Page 0x00B7 = Microphone", a platform API behavior, a protocol semantic | Authoritative citation REQUIRED (URL or in-repo authoritative doc). A bare magic number is NEVER self-evidence. |
| `metric` | "≥10 users/week", "120 Hz path", coverage %, a file-size budget | Re-run the cheap source (repo check script, focused coverage run, re-read the dashboard figure). |

### Step 2 — Verify each claim (one read-only Explore pass)
Batch all of an issue's claims into a single `Explore` delegation. Per type:
- `identifier` (repo symbol): confirm it exists at HEAD and is where the claim says → `VERIFIED` with
  `file:line`; not found / wrong location → `REFUTED` (or `UNVERIFIED` if the claim's location was vague).
- `feasibility`: reason from what the cited code actually does. **Contract feasibility runs the repo's
  `contract-validate` checklist + its Guardrails, and consults the repo's authoritative contract docs**
  (see the repo overlay section when present). A `contract-validate` backward-compat FAIL on a contract
  claim `REFUTES` any "no change needed / no migration" assertion.
- `external-spec`: web-fetch an authoritative source → `VERIFIED` only with a citation URL. Web unavailable
  ⇒ `UNVERIFIED (web-unavailable)` — never guess. (In-repo authoritative docs often refute locally even
  with no web.)
- `metric`: re-run the cheap source → `VERIFIED` with output; else `UNVERIFIED` naming the source.

### Step 3 — Per-claim verdict
- **VERIFIED** — positive evidence (file:line / citation / re-run output). ONLY these may be stated as fact.
- **UNVERIFIED** — can neither confirm nor refute (vague reference, web unavailable, unverifiable source).
  Must be downgraded to an open question or filed under an "Unverified assumptions" section.
- **REFUTED** — a positive contradiction. Blocks filing.

### Step 4 — Gate decision
- **BLOCK** — ≥1 `REFUTED`. Do NOT file. Return the required corrections; caller revises/drops and re-runs.
- **PASS-WITH-LABEL** — no `REFUTED`, but ≥1 `UNVERIFIED` specific. Caller may file ONLY after: adding the
  `needs-feasibility-review` and/or `assumption-unverified` label, adding an "## Unverified assumptions"
  section, and demoting those specifics from assertion to open question.
- **PASS** — only `VERIFIED` facts stated as fact. File as drafted.

## Output format (the gate's return value)
```
## Issue Evidence Gate — Verdict

### Gate decision: PASS / PASS-WITH-LABEL / BLOCK

### Claim ledger
| # | Claim (verbatim) | Type | Verdict | Evidence |
|---|---|---|---|---|
| 1 | "<spec claim>" | external-spec | REFUTED | <authoritative source contradicting it> <URL> |
| 2 | "<no-change-needed claim>" | feasibility | REFUTED | <contract doc file:line>; contract-validate backward-compat FAIL. |
| 3 | "<symbol exists>" | identifier | VERIFIED | <repo file:line> |

### Required revisions (only on BLOCK / PASS-WITH-LABEL)
- [BLOCK] Correct or drop claim #1 …
- [LABEL] Add `needs-feasibility-review` + an "Unverified assumptions" entry for claim #N …

### Gate notes
- Web access: available / UNAVAILABLE.   Claims: N · VERIFIED a · UNVERIFIED b · REFUTED c
```

## Reuse of contract-validate (no reinvented contract logic)
This gate embeds NO protocol byte knowledge. For contract claims it loads `contract-validate`, applies its
contract checklist and **Guardrails**, and maps the result: check `pass` → `VERIFIED`; `warn`/unsure →
`UNVERIFIED` (flag for manual review); `fail` → `REFUTED`. This keeps `contract-validate` the single
contract source of truth at both PR time and issue-filing time.

## Guardrails
- Read-only. Never modify files; never file or edit issues; only return the verdict.
- A specific value with no citation (e.g. an isolated protocol usage code) is `UNVERIFIED` by definition.
- `REFUTED` requires a positive contradiction (a citation or a `contract-validate` FAIL), not mere absence —
  absence is `UNVERIFIED`. This avoids over-blocking.
- Prefer returning a crisp, compact ledger over verbose analysis; the heavy reading happens in the
  delegated Explore pass.
