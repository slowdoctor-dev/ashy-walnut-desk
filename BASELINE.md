# BASELINE — ashy-walnut-desk

> Single source of truth for what awd is.
> If something here conflicts with anywhere else in this repo, this file wins.

---

## 1. Identity

| | |
|---|---|
| **Name** | ashy-walnut-desk |
| **Module** | `AshyWalnutDesk` / app `ashy_walnut_desk` |
| **Tagline** | The desk gets wiser with every reply. |
| **License** | MIT |
| **Hosting** | `github.com/slowdoctor-dev/ashy-walnut-desk` (Public) |

## 2. What it is

A communications platform for regulated-service businesses.

awd combines a customer record system, a multi-channel inbox, AI draft
generation, an operational knowledge layer, and an auditable approve-then-send
pipeline. Every outbound message goes through human approval with a
5-second countdown before sending.

Built on Elixir + Ash + Phoenix LiveView. Self-hosted, single-instance,
domain-configurable.

## 3. Who it's for

Small regulated-service organizations where:

- A small team handles customer/client communications
- Replies require domain judgment (not generic chatbot answers)
- Audit trail matters (regulatory, professional liability, or both)
- The team prefers self-host over SaaS

The framework is **domain-agnostic** by design (ADR-006). The first
target domain — and any specific compliance content — lives in a
separate private deployment repo (ADR-010).

## 4. Three-axis architecture

awd is structured along three orthogonal concerns:

- **Identity (Who/When)** — client/customer records, encounters, consent
- **Interaction (How)** — conversations, messages, channels, drafts, audit
- **Knowledge (What)** — manuals, guardrails, personas, references

An overview layer aggregates above the three axes (read-only). Meta-ops
(system admin) sits sideways, invisible to most users.

See `specs/architecture.md` for full structural details.

## 5. Stack

| Layer | Choice |
|---|---|
| Language | Elixir 1.17+ / OTP 27+ |
| Framework | Phoenix 1.7+ + LiveView 0.20+ |
| Resource model | Ash 3.0+ (postgres, phoenix, authentication, oban, paper_trail, graphql, admin, ai) |
| Database | PostgreSQL 16 + pgvector + pg_trgm |
| LLM client | Anthropic API direct via Req (no Python service) |
| Frontend | LiveView only (no separate SPA) |
| Container | Docker for local development |
| CI | GitHub Actions |

## 6. Key ADRs (17 total)

| ADR | Title | Status |
|---|---|---|
| ADR-001 | Elixir + Ash over Go/Python/Rails | Accepted |
| ADR-002 | Three-axis model | Accepted |
| ADR-003 | Single PostgreSQL with pgvector | Accepted |
| ADR-004 | Anthropic direct, no Python service | Accepted |
| ADR-005 | Human approval required for all sends | Accepted |
| ADR-006 | Domain as configuration, not fork | Accepted |
| ADR-008 | LiveView only, no separate SPA | Accepted |
| ADR-009 | Phoenix.PubSub + Oban for messaging | Accepted |
| ADR-010 | Deployment instance as private repo | Accepted |
| ADR-011 | Regulated services as the first target | Accepted |
| ADR-012 | Single instance, multi-account workspace | Accepted |
| ADR-013 | 5-second countdown before send | Accepted |
| ADR-014 | AGENTS.md as universal agent source | Accepted |
| ADR-015 | SDD with BMAD + GSD methodology | Accepted |
| ADR-016 | Four-stage record chain for communications | Accepted |
| ADR-017 | From-scratch on Ash, not composing existing OSS | Accepted |
| ADR-018 | Seasoning as multi-year scope structure | Accepted |

Full text in `specs/decisions/`.

## 7. Phase Roadmap (Season 1)

Each phase is a working-system increment. Not time-bound; complete when
its acceptance criteria are met.

```
Phase 0  Foundation     — Phoenix scaffold + Ash + auth + audit + i18n
Phase 1  Core Domain    — Identity-axis resources
Phase 2  Messaging      — Interaction-axis resources with four-stage chain
Phase 3  Channel        — first real channel adapter integration
Phase 4  AI Drafts      — AI-generated drafts with countdown + guardrails
Phase 5  Knowledge      — pgvector RAG over Manual/Persona content
```

Phase 0 has detailed requirements and Story 0.1 ready. Subsequent phases
are described in one line above; their detailed requirements are written
by the BMAD Analyst persona at the start of each phase (just-in-time spec
per AGENTS.md §3 and the SDD methodology in `docs/methodology.md`).

Phase 0-5 together form **Season 1** (single deployment, single domain).
Later seasons exist as possibilities, not commitments (ADR-018).

## 8. Methodology

SDD (Specification-Driven Development).

Two-layer:

- **BMAD** at phase boundaries (Analyst → Architect → PM personas)
- **GSD** for daily story work (Discuss → Plan → Execute → Verify)

Specs live in `specs/`. Code is derived from specs. Specs and code travel
together in the same commit.

LLM-agnostic per AGENTS.md (Linux Foundation convention); works with
Claude Code, Codex CLI, Gemini CLI, or any agent that reads AGENTS.md.

See `docs/methodology.md` and `prompts/` for persona prompts.

## 9. Compliance posture

The framework provides hooks; the specific regulations are
jurisdiction-dependent and operator-dependent. The framework ships
without jurisdiction-specific content. Each deployment fills
`specs/compliance/` with its own legal-reviewed documents.

Framework-level safety features:

- Hash-chained audit trail (ADR-016)
- 5-second countdown before all sends (ADR-013)
- Sensitive field marking (Ash policies)
- Auto-appended AI-assistance disclosure on drafts
- Versioned Consent resource pattern

**Nothing in this repo is legal advice.** Each deployment needs its own
legal review.

## 10. Repo strategy

Per ADR-010:

- **This repo**: the framework. No real customer data, no
  jurisdiction-specific content, no deployment configuration.
- **Deployment instance** (private, separate repo): jurisdiction-specific
  compliance, real customer ontology, channel credentials, deployment
  customizations.

A deployer clones this repo, builds their private deployment repo from
the same framework, and configures their domain via Manuals, Personas,
Guardrails — not by forking the framework.

## 11. Inviolable rules

These rules cannot be overridden without explicit ADR supersession:

1. No autonomous send. Human approval, always (ADR-005).
2. 5-second countdown before every send (ADR-013).
3. Audit trail on every state transition (ADR-016).
4. Sensitive fields marked `sensitive? true` in resources.
5. No raw credentials in code or specs.
6. AI-generated content carries an AI-assistance disclosure.
7. AGENTS.md must be readable and current; agents read it first.

## 12. External dependencies (deployer adds)

A real deployment requires the deployer to obtain:

- LLM provider account (Anthropic by default, see ADR-004)
- Channel provider account(s) for the chosen channel(s)
- Domain + TLS (Cloudflare Tunnel is the easy path)
- Hosting infrastructure
- Legal review for the deployment's jurisdiction
- End-user consent infrastructure for the deployment's jurisdiction

The framework points to these needs but does not provide them.

## 13. Where to start

You are at **Phase -1** (planning complete, Phase 0 next).

1. Read `AGENTS.md` (how AI agents work in this repo)
2. Read `specs/architecture.md` (the three-axis structure)
3. Read `specs/phase-0/requirements.md` (Phase 0 scope)
4. Read `specs/phase-0/stories/story-0.1.md` (exemplar story)
5. Run `./scripts/status.sh` for current state
6. Follow `docs/first-week-plan.md` for Day 1-7

Day 2 onward uses BMAD personas; see `prompts/`.

## 14. Heritage

awd is inspired by — but not bound to — patterns from:

- HubSpot Service Hub (three-axis service model concept)
- Augmentative AI in regulated domains (AI assists, humans decide)
- The seasoned-hand SDD scaffold (this repo's structural pattern)
- Slow-medicine and craft-software philosophy (judgment > velocity)
- BMAD-METHOD and GSD methodologies

awd is NOT a fork of any of the above. Each connection is conceptual.
