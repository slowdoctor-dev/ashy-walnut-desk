# ADR-018: Seasoning as Multi-Year Scope Structure

**Status**: Accepted
**Date**: 2026-05
**Deciders**: maintainer

---

## Context

awd is positioned as a long-term project. Without explicit scope
structure, the project risks:

- Endless scope creep ("one more feature")
- Premature commitment to features that may not be needed
- Confusion between current commitment and future possibility

A scope-structuring discipline is needed.

## Options considered

### Option 1: No structure, one continuous roadmap

- Pros: simplicity
- Cons: no natural stopping points; scope discipline weak

### Option 2: Strict phases only

- Pros: matches SDD methodology
- Cons: doesn't distinguish "ship-then-evolve" milestones from
  "expand-scope" milestones

### Option 3: Seasons as multi-phase epochs (chosen)

- Pros:
  - Clear "DONE for now" markers
  - Communicates priorities without committing to dates
  - Allows mid-stream re-evaluation between seasons
- Cons: extra terminology

## Decision

Adopt **seasons** as a layer above phases:

- A **phase** is a working-system increment (Phase 0-N, internal cadence)
- A **season** is a multi-phase epoch with a clear scope and "done" definition

Each season has:
- A scope statement (what's in / out)
- A done definition (when is the season complete)
- A closure ritual (retrospective, decision: continue or pause)

Number of seasons is open-ended. Only the current season is detailed; future
seasons exist as seeds only until reached. Season 1 is committed; later
seasons are options, not commitments.

## Structure

Seasons live in `specs/seasons/<SEASON-N>.md` (added by deployer when
the project reaches that scope). The framework itself ships without
season files — those describe a specific deployment's trajectory, not
the framework's.

A framework deployer typically structures their work as:

- **Season 1**: single deployment, single domain, single channel
- **Season 2**: multi-domain abstraction
- **Season 3**: commercialization decision (SaaS / managed self-host / etc.)
- **Season 4+**: aspirational

The framework neither prescribes nor restricts the seasoning pattern.

## Consequences

### Positive
- Scope decisions have a natural home
- Future possibilities documented without commitment
- Season closure becomes a natural decision point
- BASELINE.md can stay focused on current season

### Negative / accepted trade-offs
- Extra terminology
- Risk of "next season thinking" creeping into current work
  (mitigate via SDD: spec the current season, sketch the next)

## References

- AGENTS.md §3 (phase-by-phase development)
- ADR-006 (domain as configuration, not code)
- `specs/seasons/` (created by deployer, not the framework)
