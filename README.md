# ashy-walnut-desk

> A digital front-desk system for regulated-service businesses:
> Identity + Interaction + Knowledge, with AI augmentation and human approval.
>
> *The desk gets wiser with every reply.*

🚧 **Status: Alpha — building in public.**

## Status

**Phases 0–5 are all shipped — Season 1's planned scope is
complete**: foundation, Identity axis, Interaction axis (four-stage
chain + hash-chained audit), Twilio SMS channel, AI drafts with
validator + approval + countdown, and Knowledge/RAG-grounded
generation. Next boundary: Season 1 retrospective review
([`docs/retrospectives/season-1.md`](docs/retrospectives/season-1.md))
and ADR-027/ADR-028 acceptance before any Season 2 commitment
(ADR-018). Run `./scripts/status.sh` for the live picture.

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

## Phase 1 timeline screenshots

Identity-timeline UX evidence lives in
[`docs/phase-1-screenshots/`](docs/phase-1-screenshots/) and is regenerable
from `just`:

```bash
just dev                      # in one terminal
just screenshots              # in another — seeds demo data + captures PNGs
```

Requires Python 3 + the `playwright` package (`pip install playwright` and
`python3 -m playwright install chromium` if Chromium isn't already cached).

## Phase 2 Inbox screenshots

Inbox chain UX evidence lives in
[`docs/phase-2-screenshots/`](docs/phase-2-screenshots/) and is regenerable
from `just`:

```bash
just dev                      # in one terminal
just phase2-screenshots       # in another — seeds demo data + captures PNGs
```

Uses the same Python/Playwright setup as Phase 1.

## Phase 3 deployer runbook — Twilio SMS

Phase 3 ships the first real-channel adapter (Twilio SMS). A
deployer activating the channel needs three things:

1. **Twilio credentials in the environment.** Set the following on
   the host (or in the deployer's private repo's `.env`):

   ```bash
   export TWILIO_ACCOUNT_SID=AC…
   export TWILIO_AUTH_TOKEN=…
   export TWILIO_FROM_NUMBER=+1…
   ```

   The Phoenix endpoint refuses to boot in `:prod` without these.

2. **Register the channel.** Once an admin is signed in, register a
   `Channel` row pointing at the Twilio adapter:

   ```elixir
   Ash.create!(
     AshyWalnutDesk.Interaction.Channel,
     %{
       slug: "twilio-sms",
       display_name: "Twilio SMS",
       adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio"
     },
     action: :register_channel,
     actor: admin
   )
   ```

3. **Run the preflight check.**

   ```bash
   mix phase3.webhook.preflight
   ```

   This Mix task exits non-zero if any of `TWILIO_ACCOUNT_SID`,
   `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`, or the
   `Channel{slug: "twilio-sms"}` row is missing. Wire it into the
   deploy script before the first outbound send goes live.

4. **Webhook URL.** Configure Twilio's "Messaging webhook" URL to
   `https://<your-host>/webhook/twilio`. The endpoint is throttled
   to 60 req/min/IP (`:webhook` pipeline in `router.ex`) and rejects
   any payload whose `X-Twilio-Signature` HMAC does not match
   `TWILIO_AUTH_TOKEN`.

Operational visibility for chain continuity lives at
`/audit/chain` (admin only — see story 3.7). Verify chain integrity
from the CLI any time with `mix audit.verify`.

Architecture details: [`specs/phase-3/architecture.md`](specs/phase-3/architecture.md).

## Phase 4 deployer runbook — AI drafts

Phase 4 ships AI draft generation (Anthropic direct via Req, ADR-025).
Drafts are generated on operator request, validated by the safety
stack, and still require explicit human approval + the 5-second
countdown before any send (ADR-005/ADR-013 — generation never sends).
Activating it requires four steps:

1. **Provider key in the environment.** Set on the host (or in the
   deployer's private repo's `.env`):

   ```bash
   export ANTHROPIC_API_KEY=sk-ant-…
   ```

   `config/runtime.exs` refuses to boot in `:prod` without it. The
   key is never logged and never persisted into `Draft.ai_*` fields
   or `AuditEvent` rows.

2. **Check the model allowlist.** `config/config.exs` ships
   `:ai_model_allowlist` (`claude-sonnet-4-6`, `claude-opus-4-7`)
   and `:default_model` (`claude-sonnet-4-6`). A deployment that
   wants a different model set overrides both in its release config;
   `:default_model` and every Persona `model_override` must stay
   inside the allowlist.

3. **Create at least one Persona.** Personas carry the deployment's
   system prompt, guardrail notes, disclosure footer, and optional
   model override — tone is configuration, not code (AGENTS.md §6).
   Once an admin is signed in:

   ```elixir
   Ash.create!(
     AshyWalnutDesk.Knowledge.Persona,
     %{
       name: "Front-desk default",
       slug: "front-desk-default",
       system_prompt: "…deployment-reviewed base instruction…",
       disclosure_text: "AI-assisted draft; reviewed by a human operator.",
       guardrail_notes: "…deployment guardrails…",
       model_override: nil
     },
     action: :create,
     actor: admin
   )
   ```

4. **Run the preflight check.**

   ```bash
   mix phase4.ai.preflight                 # full check, incl. one low-token Anthropic call
   mix phase4.ai.preflight --skip-network  # offline/CI variant
   ```

   The task exits non-zero when `ANTHROPIC_API_KEY` is missing, when
   `:default_model` or `:ai_adapter` falls outside its allowlist,
   when an active Persona's `model_override` was stranded by an
   allowlist change, or (network mode) when Anthropic rejects the
   key. Wire it into the deploy script next to
   `mix phase3.webhook.preflight`.

Phase-close verification runs from a clean environment with:

```bash
just verify                              # format + credo + test + spec-check
mix phase4.ai.preflight --skip-network   # AI config gate (offline)
mix audit.verify                         # hash-chain integrity
```

Architecture details: [`specs/phase-4/architecture.md`](specs/phase-4/architecture.md).

## Phase 5 deployer runbook — Knowledge / RAG

Phase 5 grounds AI drafts in deployment-authored Manual content
(pgvector retrieval with a pg_trgm lexical fallback, ADR-026).
Retrieval is context-in only — approval + countdown + audit invariants
are untouched. Activating it requires three steps:

1. **Choose the embedding posture — explicitly.** The Anthropic
   Messages API has no embeddings endpoint, so vector retrieval needs
   a second provider. `config/runtime.exs` refuses to boot in `:prod`
   until you set:

   ```bash
   export EMBEDDING_ADAPTER=voyage   # external embeddings via Voyage AI
   export VOYAGE_API_KEY=pa-…        # required with voyage
   # — or —
   export EMBEDDING_ADAPTER=none     # no external embeddings; lexical-only retrieval
   ```

   **`voyage` sends Manual content to the external embedding
   provider.** Review your data-processing agreement and
   `specs/compliance/` posture first; `none` keeps all knowledge
   in-instance and retrieval degrades to pg_trgm lexical matching.

2. **Author Manuals.** Admins manage them at `/manuals` (list, edit,
   version history, archive/restore). Every authoring write enqueues
   background chunk+embed indexing (`:knowledge_indexing` queue);
   nothing blocks the operator request path. Generation candidates
   show a `knowledge: …` badge with the retrieval mode and excerpt
   count; full provenance persists on `Draft.ai_retrieval`.

3. **Run the preflight check.**

   ```bash
   mix phase5.knowledge.preflight                 # incl. one low-cost embed call
   mix phase5.knowledge.preflight --skip-network  # offline/CI variant
   ```

   The task exits non-zero on a non-allowlisted embedder, an
   `:embedding_dimension` that disagrees with the `manual_chunks`
   vector column or the configured model, or a missing
   `VOYAGE_API_KEY` when the Voyage adapter is configured. Wire it in
   next to the Phase 3/4 preflights.

Phase-close verification runs from a clean environment with:

```bash
just verify                                     # format + credo + test + spec-check
mix phase5.knowledge.preflight --skip-network   # knowledge config gate (offline)
mix audit.verify                                # hash-chain integrity
```

Architecture details: [`specs/phase-5/architecture.md`](specs/phase-5/architecture.md).

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

This repo = **public framework** (Apache 2.0, no real customer data, no
jurisdiction-specific content). A deployer maintains a separate private
repo for their deployment-specific content: real customer ontology,
jurisdiction-specific compliance, credentials.

This separation ensures:
- Real customer data never enters the public repo
- Deployment-specific decisions stay private
- The framework remains domain-agnostic

See ADR-010 in [`specs/decisions/`](specs/decisions/).

## License

[Apache License 2.0](LICENSE).

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
