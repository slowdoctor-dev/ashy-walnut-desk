# Phase 0 — Requirements

## 1. Goal

Establish a working Elixir + Phoenix + Ash project with all foundational
dependencies, authentication, audit, and CI in place. No domain logic yet.

End state: a developer can clone, run `just setup && just dev`, log in,
see a welcome LiveView, and CI is green on push.

## 2. Acceptance criteria (phase-level)

- [ ] `mix phx.server` runs without errors
- [ ] `mix test` passes (initial test suite)
- [ ] `just verify` (format + credo + test + spec-check) all green
- [ ] GitHub Actions CI green on push to `main`
- [ ] Welcome LiveView shows project name + version
- [ ] User can sign up + log in (AshAuthentication via magic link)
- [ ] AshPaperTrail enabled (no resources to audit yet, just config)
- [ ] Oban configured with queues: `default`, `messages`, `ai`, `reindex`
- [ ] PostgreSQL 16 + pgvector + pg_trgm extensions enabled
- [ ] gettext working (basic strings translated; deployer chooses locales)
- [ ] All foundational ADRs documented
- [ ] README.md has working quick-start

## 3. Scope

### In scope
- Phoenix project skeleton with Ash dependencies
- PostgreSQL via Docker Compose
- AshAuthentication (magic-link, no passwords initially)
- AshPaperTrail (enabled at app level)
- Oban + queue config
- gettext for i18n (deployer adds locales)
- Welcome LiveView
- GitHub Actions CI
- Initial ADRs (ADR-001 through ADR-018)
- Documentation foundation (CHANGELOG, CONTRIBUTING, SECURITY)

### Out of scope (deferred)
- Identity / Event / Appointment resources → Phase 1
- Messaging (Conversation/Message) → Phase 2
- External channel adapters → Phase 3
- AI integration → Phase 4
- RAG / pgvector use → Phase 5
- Multi-tenancy → post-Season 1
- Production deployment → Phase 5 end

## 4. Story breakdown

| # | Story | Est | Depends on | Status |
|---|---|---|---|---|
| 0.1 | Initialize Phoenix project + Ash deps + Docker Compose | 2h | — | ready |
| 0.2 | Enable PostgreSQL extensions (pgvector + pg_trgm) | 1h | 0.1 | ready |
| 0.3 | Configure Oban with default/messages/ai/reindex queues | 1.5h | 0.1 | ready |
| 0.4 | Install AshPaperTrail at app level | 1h | 0.1 | ready |
| 0.5 | AshAuthentication install + Accounts.User + Accounts.Token | 2.5h | 0.1, 0.2 | ready |
| 0.6 | First-user-admin Ash change + race-safe constraint | 1.5h | 0.5 | ready |
| 0.7 | AshAuthentication Phoenix UI mounting | 1.5h | 0.5 | ready |
| 0.8 | WelcomeLive + gettext for Phase 0 strings | 1.5h | 0.7 | ready |
| 0.9 | GitHub Actions CI workflow | 1h | 0.1 | ready |
| 0.10 | README quick-start verification + CHANGELOG Phase 0 update | 1h | 0.6, 0.8, 0.9 | ready |
| 0.11 | Phase 0 E2E magic-link integration test | 2h | 0.6, 0.8 | ready |

Total: 11 stories, ~16.5h of new work after 0.1 (~18.5h including 0.1).

**Critical path** (longest dependency chain): `0.1 → 0.2 → 0.5 → 0.7 → 0.8 → 0.11` = 10.5h.

**Parallelizable** (after 0.1 lands, can run in separate worktrees): 0.3, 0.4, 0.9 are independent of the auth chain.

Per AGENTS.md §2, each story = one fresh AI session = one PR = one atomic commit.

## 5. Dependencies

### External
- PostgreSQL 16 with pgvector extension (Docker image)
- Elixir 1.17+ / OTP 27+ (asdf)
- Node.js 20+ (for asset pipeline)
- GitHub account + repo (for CI)

### Internal
- None (this is Phase 0)

## 6. Risks

| Risk | Mitigation |
|---|---|
| Elixir learning curve slows Phase 0 | Stories sized 1-3h; spec is the bridge |
| Ash + Phoenix version conflicts | Pin versions in `mix.exs`; use `.tool-versions` |
| CI flakes on first setup | Local `just verify` must pass before push |
| Magic-link auth requires SMTP | Use local mailer in dev (Swoosh adapter) |

## 7. Open questions (for Architect)

- [ ] Single app vs umbrella project? (Default: single)
- [ ] AshAuthentication strategy: magic-link only, or also password? (Default: magic-link only)
- [ ] Tailwind v4 or v3? (Whatever Phoenix 1.7 installs)
- [ ] CI: GitHub-hosted runner or self-hosted? (Default: GitHub-hosted)
- [ ] Initial admin user: seeded or created via signup? (Default: signup, first user gets admin role)

These should be resolved in `specs/phase-0/architecture.md` by the
Architect persona.
