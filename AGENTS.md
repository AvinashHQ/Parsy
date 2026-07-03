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

## Dev environment (this machine)

<!-- Machine-local facts that differ from README — verified 2026-07-01. -->

- Ruby is managed by **mise**, not rbenv (rbenv is not installed). Run `ruby bin/rails ...` directly — `rbenv exec` fails with "command not found".
- Postgres is Homebrew `postgresql@16` and not always running: `brew services start postgresql@16`, then `ruby bin/rails db:test:prepare`. Tests fail at load time with `ConnectionNotEstablished` while it's down.
- No `timeout` CLI on this shell — drop the README's `timeout 180 ...` prefixes.
- Gems are shared machine-wide across git worktrees (no per-worktree bundle path). A sibling worktree's bundle change can cause transient `Bundler::GemNotFound` in fresh processes — fix with `gem install <name> -v <pinned-version>`; don't touch Gemfile.lock.
- Ollama runs locally with `qwen3-vl:4b` and `glm-ocr` pulled — `script/run_llm_benchmark.rb` actually works here (digital PDFs ~15–70s, images ~100–240s each).
- Sign-in is invite/operator-token gated, not password auth (`SessionsController#create` → `authenticate_operator_token`). A dev user `operator@example.com` (tenant `default-tenant`) exists; reset its token via `bin/rails runner` with `User#operator_token=` (setter hashes it) rather than creating duplicates.
- Browser automation cannot fill `<input type=file>` directly (browser security): copy the fixture into `public/` temporarily, `fetch()` it same-origin, wrap the blob in a `File` via `DataTransfer`, dispatch `change`, then call `form.requestSubmit()` on the right form (generic submit selectors can match the header's sign-out button). Delete the temp file after.

## Memory

- Workspace memory page: `../avinashhq_brain/projects/parsy.md`
- Registry entry: `../projects.yaml` (slug: `parsy`)
- Memory search (works from any cwd): `qmd search "<term>" -c avinashhq -n 5`; semantic: `env -u CI qmd query "<question>" -c avinashhq --no-rerank -n 5`
- Session wrap-up: `../scripts/session-close --project parsy --summary -`


## Do not

- Do not commit secrets, tokens, credentials, or generated artifacts.
- Do not restructure this repo without recording the decision in the memory page.
