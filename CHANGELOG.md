# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added — Phase 0 (Foundation)
- Phoenix 1.7 + LiveView 1.1 scaffold on Ash 3.0 (`ash_postgres`,
  `ash_authentication`, `ash_authentication_phoenix`, `ash_oban`,
  `ash_paper_trail`); PostgreSQL 16 via `pgvector/pgvector:pg16`
  Docker Compose service bound to `127.0.0.1:5432` (story 0.1).
- Hand-authored setup migration enables PostgreSQL `vector` + `pg_trgm`
  extensions (story 0.2); `citext` setup migration added when
  AshAuthentication required it (story 0.5).
- Oban background runtime with four queues — `default`, `messages`,
  `ai`, `reindex` — supervised from the app tree (story 0.3).
- AshPaperTrail wired at the app level (`config :ash_paper_trail,
  repo: AshyWalnutDesk.Repo`) so resources can opt in per
  AGENTS.md §6 (story 0.4).
- Magic-link authentication via AshAuthentication:
  `AshyWalnutDesk.Accounts` domain, `Accounts.User`, `Accounts.Token`;
  `email` + `email_hash` (SHA-256 salted by `IDENTIFIER_HASH_SALT`)
  marked `sensitive? true`; role enum `:admin | :operator`;
  `AshPaperTrail.Resource` opted in on `User` (story 0.5).
- First-registered-user → `:admin` Ash change
  (`AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdmin`) wired into
  `:sign_in_with_magic_link`; race-safe partial unique index
  `users_one_admin_idx` on `users(role) WHERE role = 'admin'`; loser
  recovers as `:operator` via `after_transaction` retry hook
  (story 0.6).
- AshAuthentication Phoenix UI mounted on `/sign-in` + magic-link
  confirm route; Swoosh magic-link email delivery (`Swoosh.Adapters.Local`
  in dev exposed at `/dev/mailbox`, `Swoosh.Adapters.Test` in test);
  `lib/ashy_walnut_desk/mailer.ex` + `Accounts.Emails` (story 0.7).
  Required `phoenix_live_view ~> 1.1` (resolved the
  `compile.phoenix_live_view` landmine from story 0.1's spec drift).
- `AshyWalnutDeskWeb.WelcomeLive` at `/` rendering project name, app
  version (`Application.spec(:ashy_walnut_desk, :vsn)`), and sign-in
  / sign-out state; gettext baseline — all user-facing strings flow
  through `gettext/1`, English `.po` populated (story 0.8).
- GitHub Actions CI workflow (`.github/workflows/ci.yml`): five gates
  in order — `mix format --check-formatted`, `mix credo --strict`,
  `mix ash_postgres.generate_migrations --check`, `mix test`,
  `scripts/spec-check.sh` — on every push to `main` and every PR,
  with a `pgvector/pgvector:pg16` service container (story 0.9).

### Meta
- AGENTS.md §6 codifies the `Co-Authored-By` trailer rule for every
  AI tool that contributes to a commit.
- AGENTS.md §10 gotchas captured: `mix phx.new` overwrites
  `.gitignore`, AshAuthentication generators hang in non-tty
  environments, AshPostgres auto-generated migrations assume
  referenced extensions are already enabled,
  `ash_authentication_phoenix` requires `phoenix_live_view >= 1.1`.

## [0.0.0] — 2026-05-12

### Added
- Project decision: ashy-walnut-desk identity, MIT licensed
- Stack: Elixir + Phoenix + Ash + LiveView + PostgreSQL/pgvector
- Methodology: SDD with BMAD + GSD
- Three-axis architecture (Identity + Interaction + Knowledge)
- 17 foundational ADRs accepted (skeleton form for ADR-002 through ADR-015)
- Phase 0 requirements with first story drafted
- LLM-agnostic agent config (AGENTS.md universal, CLAUDE.md wrapper)

### Status
Phase -1 (planning) complete. Phase 0 (foundation) starting.
