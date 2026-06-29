# Parsy — AI Invoice Parser

Rails 8.1 modular monolith for a supervised, invite-only invoice intake and exception-review MVP.

## Source of truth

Use `invoice-parser-global-docs/` as the primary implementation source. The older `invoice-parser-rails-docs-only/` pack is retained for reference only; where it conflicts, the global pack wins.

Core boundary from the docs:

- One implementation repo and one Rails app/container image.
- Ruby 3.4.x, Rails 8.1.x, PostgreSQL, Active Storage, Solid Queue, Hotwire.
- Canonical Invoice Schema v2 as the invariant data contract.
- Generic JSON/CSV/XLSX exports first.
- `global_generic_v1` is the first-live profile.
- Regional packs and ERP adapters are post-MVP unless pilot evidence selects exactly one M6 capability.

## Local setup

```bash
rbenv local 3.4.8
bundle install
bin/rails active_storage:install # already run in this scaffold
bin/rails db:prepare
```

If `bin/rails` resolves to the macOS system Ruby, run Rails commands through rbenv explicitly:

```bash
RBENV_VERSION=3.4.8 rbenv exec ruby bin/rails zeitwerk:check
```

## Product assets copied into the app

- `contracts/invoice.schema.json`
- `contracts/region_profile.schema.json`
- `contracts/openapi.yaml`
- `prompts/extraction_system.txt`
- `prompts/extraction_user_template.txt`
- `prompts/repair_system.txt`
- `config/format_registry.yml`
- `config/region_profiles.yml`
- `config/validation_rules.yml`
- `config/field_dictionary.yml`

## Milestone source

GitHub milestones/issues are seeded from:

- `invoice-parser-global-docs/docs/08_DELIVERY_PLAN.md`
- `invoice-parser-global-docs/planning/mvp_issues.csv`
- `invoice-parser-global-docs/planning/milestone_exit_gates.csv`
- `invoice-parser-global-docs/planning/region_backlog.csv`

Critical path: `M0 → M1 → M2 → M3 → M4 → M5`. `M6` is post-MVP.
