# parsy — Agent Guide

## Scope

Parsy is a Rails invoice-parsing application: it extracts structured data from invoice documents.

This guide covers only this repository. Workspace-level routing, memory, and the
session wrap-up protocol live in `../AGENTS.md` (auto-loaded by most harnesses).

## Commands

<!-- Verified commands only. Keep in sync with `commands:` in ../projects.yaml. -->
- `dev`: `bin/rails server`
- `test`: `bin/rails test`

## Architecture

Rails 8.1.3 on Ruby 3.4.8 with PostgreSQL, default Rails layout, minitest (no rspec).
<!-- Deepen this module map after the next substantive session. -->

## Memory

- Workspace memory page: `../avinashhq_brain/projects/parsy.md`
- Registry entry: `../projects.yaml` (slug: `parsy`)


## Do not

- Do not commit secrets, tokens, credentials, or generated artifacts.
- Do not restructure this repo without recording the decision in the memory page.
