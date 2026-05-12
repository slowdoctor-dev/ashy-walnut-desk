# Architectural Decision Records (ADRs)

## What are ADRs?

ADRs document significant architectural decisions: the context, the
options considered, the decision made, and the consequences.

Each decision is one file, numbered, immutable once accepted.
Superseded decisions get a new ADR explaining why.

Format: `ADR-NNN-kebab-name.md` (e.g., `ADR-001-elixir-and-ash.md`).

## Index

| # | Title | Status | Date |
|---|---|---|---|
| 001 | Elixir + Ash over Go/Python/Rails | Accepted | 2026-05 |
| 002 | Three-axis model (Identity/Interaction/Knowledge) | Accepted | 2026-05 |
| 003 | Single PostgreSQL with pgvector | Accepted | 2026-05 |
| 004 | Anthropic direct, no Python service | Accepted | 2026-05 |
| 005 | Human approval required for all sends | Accepted | 2026-05 |
| 006 | Domain as configuration, not fork | Accepted | 2026-05 |
| 007 | Public OSS from day one | Accepted | 2026-05 |
| 008 | LiveView only, no separate SPA | Accepted | 2026-05 |
| 009 | Phoenix.PubSub + Oban for messaging | Accepted | 2026-05 |
| 010 | Deployment instance as private repo | Accepted | 2026-05 |
| 011 | Regulated services as the first target | Accepted | 2026-05 |
| 012 | Single instance, multi-account workspace | Accepted | 2026-05 |
| 013 | 5-second countdown before send | Accepted | 2026-05 |
| 014 | AGENTS.md as universal agent source | Accepted | 2026-05 |
| 015 | SDD with BMAD + GSD methodology | Accepted | 2026-05 |
| 016 | Four-stage record chain for communications | Accepted | 2026-05 |
| 017 | From-scratch on Ash, not composing existing OSS | Accepted | 2026-05 |
| 018 | Seasoning as multi-year scope structure | Accepted | 2026-05 |

## When to write an ADR

You should write an ADR when:
- A technology, library, or framework is being chosen
- A pattern or convention is being established repo-wide
- A security, privacy, or compliance decision is being made
- A trade-off is being made between competing alternatives
- A previous ADR is being superseded

You should NOT write an ADR for:
- Implementation details (use specs or code comments)
- Bug fixes
- Minor refactors
- Personal preferences without trade-off

## Template

See `template.md` in this directory.
