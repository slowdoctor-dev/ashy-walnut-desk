# ADR-001: Elixir + Ash over Go / Python / Rails

**Status**: Accepted
**Date**: 2026-05-11
**Deciders**: maintainer

---

## Context

We need to build a system that has three major concerns running concurrently:
1. **Identity** — client/customer records with audit + policies
2. **Interaction** — multi-channel messaging with real-time updates
3. **Knowledge** — ontology with vector search

Plus AI integration and human-in-the-loop workflows.

Single-developer project. ~5 months to working system.

## Options considered

### Option 1: Go + GORM + custom

- Pros: fast, simple deployment, large community
- Cons: must hand-write everything (CRM, audit, policies, real-time);
  no opinionated framework; lots of glue code

### Option 2: Python + Django + DRF

- Pros: mature CRM/admin patterns, batteries-included
- Cons: GIL limits concurrency; LiveView equivalent (HTMX) less polished;
  channel adapters via Celery less elegant than Oban

### Option 3: Rails + Hotwire + Sidekiq

- Pros: mature CRM patterns, Hotwire is good
- Cons: Ruby concurrency limited; no Ash-equivalent (must hand-roll
  resources, actions, policies)

### Option 4: Elixir + Phoenix + Ash

- Pros:
  - BEAM concurrency: 1000s of channel/draft processes naturally
  - Ash 3.0: declarative resources eliminate 60-80% of CRUD code
  - LiveView: real-time UI without separate SPA
  - AshAuthentication, AshPaperTrail, AshOban: pre-built for our needs
  - Single language end-to-end (no Python sidecar)
- Cons:
  - Steep learning curve for solo dev coming from Python/JS
  - Smaller ecosystem than Rails/Django
  - Hiring difficulty if project grows beyond solo

## Decision

We chose **Option 4: Elixir + Phoenix + Ash**.

Reasoning:
- Ash declarative model maps cleanly to our domain (resources, actions,
  policies, audit per Resource)
- BEAM concurrency handles channel + AI + inbox loads naturally
- LiveView eliminates separate frontend project (1 person, 1 stack)
- 5-month learning curve is acceptable given the leverage Ash provides
- Smaller community is acceptable for solo OSS project
- Hiring concern not relevant in alpha; can revisit Phase 5+

## Consequences

### Positive
- One language, one repo, one deployment
- Pre-built audit, auth, policies (AshPaperTrail, AshAuthentication)
- Real-time UI without separate WebSocket layer
- Phoenix's reputation for reliability (WhatsApp, Discord)

### Negative / accepted trade-offs
- Solo dev must learn Elixir/Erlang
- Smaller hiring pool if scaling team
- Some libraries (specialized NLP, scientific computing) better in Python — must wrap via NIF or REST

### Follow-up actions
- [x] Pin Elixir 1.17 / OTP 27 in `.tool-versions`
- [x] Add Ash deps in `mix.exs` (Phase 0, story 0.1)
- [ ] First two weeks: complete "Elixir in Action" Ch 1-7
- [ ] Phase 0 retrospective: assess learning curve, decide if scope adjustment needed

## References

- Related ADRs: ADR-008 (LiveView only)
- Ash Framework: https://ash-hq.org
- Phoenix: https://phoenixframework.org
- BEAM concurrency: https://www.erlang.org/blog/the-beam-virtual-machine/
