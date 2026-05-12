# ashy-walnut-desk

> A digital front-desk system for regulated-service businesses:
> Identity + Interaction + Knowledge, with AI augmentation and human approval.
>
> *The desk gets wiser with every reply.*

🚧 **Status: Alpha — building in public.**

## Status

**Phase -1** — Planning complete. Phase 0 (foundation) starting.

For the full picture, start with [`BASELINE.md`](BASELINE.md) — single
entry point covering identity, architecture, methodology, and current state.

System design: [`specs/architecture.md`](specs/architecture.md).

## What

A self-hostable digital front-desk system organized around three coequal
axes:

- **Identity** — who/when (client/customer records, encounters, consent)
- **Interaction** — how (multi-channel messages, drafts, audit chain)
- **Knowledge** — what (manuals, guardrails, personas)

AI generates message drafts; humans review and approve before sending.
No autonomous outbound. 5-second countdown before every send.

## Why

Customer-facing teams in regulated-service businesses (healthcare clinics,
law firms, real-estate agencies, professional services) need a unified
workspace for messaging, customer records, and domain knowledge — without
giving data to a SaaS vendor and without losing human judgment.

## Tech Stack

- Elixir 1.17+ / OTP 27+
- Phoenix 1.7+ with LiveView
- Ash Framework 3.0+
- PostgreSQL 16 (pgvector + pg_trgm)
- Anthropic API (direct, no intermediate service)

## Methodology

**Spec-Driven Development (SDD)** — every change starts with a spec.

- **BMAD** personas (Analyst → Architect → PM) at the start of each phase
- **GSD** workflow (Discuss → Plan → Execute → Verify) for every story
- One story = 1-3 hours = 1 PR = 1 atomic commit
- Each story uses a fresh AI session — spec is the bridge

See [`docs/methodology.md`](docs/methodology.md).

## Quick Start

Prerequisites: `git`, `docker` (for the PostgreSQL service container),
and Elixir/OTP matching `.tool-versions` (1.17.3 + 27.1.2) — easiest
via [`asdf`](https://asdf-vm.com/) or [`mise`](https://mise.jdx.dev/).

```bash
# 1. Clone
git clone https://github.com/slowdoctor-dev/ashy-walnut-desk
cd ashy-walnut-desk

# 2. Install the task runner
brew install just                # macOS
# or: cargo install just          # any platform
# or: apt install just            # Debian/Ubuntu (may be older)

# 3. Mix deps + .env scaffold
just setup

# 4. Start Postgres (pgvector/pgvector:pg16) on 127.0.0.1:5432
docker compose up -d

# 5. Create DB + run all migrations
mix ecto.setup

# 6. Start the dev server
just dev                         # serves http://localhost:4000

# 7. Sign up — visit http://localhost:4000/sign-in, enter your email.
#    The magic-link email lands in the dev mailbox preview at
#    http://localhost:4000/dev/mailbox. Click the link.
#    The first registered user gets `:admin`; subsequent users get
#    `:operator` (DB-enforced via the users_one_admin_idx partial index).

# 8. After signing in, http://localhost:4000 renders WelcomeLive with
#    your email + a sign-out link.

# Verify everything is green at any point:
just verify                      # mix format + credo + test + spec-check
just status                      # phase + story progress
```

See [`docs/first-week-plan.md`](docs/first-week-plan.md) for the full
Day 1 → Day 7 action plan, and run `just story-prompt` in a fresh AI
session when you're ready to start the next story.

## AI tool compatibility

This project is **LLM-agnostic**. Any AGENTS.md-compatible AI coding tool
will produce equivalent results.

| Tool | Config file | Status |
|---|---|---|
| Codex CLI | `AGENTS.md` | ✅ Native |
| Cursor 0.50+ | `AGENTS.md` | ✅ Native |
| Claude Code | `CLAUDE.md` (imports `AGENTS.md`) | ✅ Via import |
| Cline | `AGENTS.md` | ✅ Native |
| Aider | `AGENTS.md` | ✅ Native |

See [`AGENTS.md`](AGENTS.md) — the source of truth for all agents.

## Documentation

- [BASELINE](BASELINE.md) — single entry point
- [Architecture](specs/architecture.md)
- [Methodology (BMAD + GSD)](docs/methodology.md)
- [First-week plan](docs/first-week-plan.md)
- [Using Claude and Codex](docs/using-claude-and-codex.md)
- [ADRs](specs/decisions/)

## Two-track repository

This repo = **public framework** (MIT, no real customer data, no
jurisdiction-specific content). A deployer maintains a separate private
repo for their deployment-specific content: real customer ontology,
jurisdiction-specific compliance, credentials.

This separation ensures:
- Real customer data never enters the public repo
- Deployment-specific decisions stay private
- The framework remains domain-agnostic

See ADR-010 in [`specs/decisions/`](specs/decisions/).

## License

[MIT](LICENSE).

## Contributing

Pick a story from `specs/phase-N/stories/`, follow the GSD workflow in
`prompts/gsd-execute-story.md`, one PR per story.

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Disclaimer

⚠️ This software is provided "AS IS". It is **NOT** certified for use in
any regulated production setting without further review, certification,
and local regulatory compliance by the deployer. See [`DISCLAIMER.md`](DISCLAIMER.md).

## Acknowledgments

Architectural inspiration (no runtime dependency):

- HubSpot Service Hub — three-axis service model
- BMAD-METHOD and GSD — SDD methodology
- seasoned-hand — SDD scaffold pattern
- The slow-medicine and craft-software communities — human-paced philosophy
