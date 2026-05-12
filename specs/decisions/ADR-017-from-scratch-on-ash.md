# ADR-017: From-Scratch on Ash, Not Composing Existing OSS Projects

**Status**: Accepted
**Date**: 2026-05
**Deciders**: maintainer

---

## Context

Initial design discussions considered shortcuts: take an existing OSS
CRM (for the Identity axis) and an existing OSS multi-channel inbox
(for the Interaction axis), integrate them, ship faster.

This pattern is tempting because:
- Each component is mature
- "Reuse over rebuild" is a familiar mantra
- The combined timeline looks shorter on paper

After analysis, this approach was rejected for awd.

## Options considered

### Option 1: Integrate existing CRM + existing inbox

- Pros: faster initial timeline (months vs quarters)
- Cons:
  - Three languages to maintain (the two integrated stacks + glue)
  - Two upstream projects to track for security and breaking changes
  - Localization burden multiplied
  - Domain-specific safety patterns (audit chain, approval gating) harder
    to enforce across project boundaries
  - Hostile integration: neither upstream is designed to be composed by
    a third party

### Option 2: Fork both, customize freely

- Pros: full control over the customizations
- Cons: maintenance burden of two forks; loss of upstream improvements;
  worst of both worlds

### Option 3: From-scratch on Elixir + Ash (chosen)

- Pros:
  - Single language end-to-end
  - Single deployment artifact
  - Ash provides much of the CRUD/policy/audit boilerplate that would
    otherwise come from the existing CRM
  - LiveView provides real-time UI without a separate frontend stack
  - Domain-specific safety patterns enforced uniformly from day one
- Cons: longer initial timeline (~5+ months instead of ~2-3)

### Option 4: Use just the CRM, no inbox

- Pros: less complexity than Option 1
- Cons: still need messaging eventually; would build messaging in Elixir
  while CRM is in a different language — same boundary problem deferred

## Decision

Adopt **Option 3: From-scratch on Elixir + Ash**.

Beyond the technical reasoning:

1. **Learning value**: building on Ash deeply teaches the framework
   instead of treating it as glue
2. **SDD methodology fit**: a fresh codebase with consistent conventions
   is easier to spec-drive than wrangling two upstream projects
3. **Domain specificity**: safety + regulatory + workflow concerns are
   tightly coupled; composing them across project boundaries creates
   perpetual maintenance pain
4. **Two-track repo strategy** (ADR-010): public framework + private
   instance. Multi-upstream composition would muddy this boundary.

## Consequences

### Positive
- Single Elixir codebase
- No upstream project drama
- Safety patterns enforced uniformly
- SDD scales cleanly
- Skills compound (Ash, LiveView, Phoenix all reinforce each other)

### Negative / accepted trade-offs
- Longer initial timeline
- Must design inbox UX rather than inherit it
- Must define each Ash Resource rather than pre-built object types

## References

- ADR-001 (Elixir+Ash stack)
- ADR-008 (LiveView only, no separate SPA)
- ADR-010 (two-track repos: public framework, private instance)
