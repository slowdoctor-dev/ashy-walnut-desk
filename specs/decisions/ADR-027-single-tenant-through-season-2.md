# ADR-027: Stay single-tenant (per-deployment instance) through Season 2

**Status**: Proposed
**Date**: 2026-07-11
**Deciders**: solo maintainer (drafted at the Season 1 retrospective)

---

## Context

`specs/architecture.md §13` deferred the multi-tenancy question to the
end of Phase 5: *"Multi-tenant: per-deployment schema or shared with
tenant_id?"* Phase 5 is shipped, so the question is due.

Season 1 evidence that bears on it:

- ADR-010/ADR-012 already give each deployment its own instance +
  private repo. Isolation exists at the infrastructure layer, where it
  is strongest.
- Several shipped mechanisms are instance-global by construction: the
  one-admin partial unique index (`users_one_admin_idx`), audit
  `chain_topic` namespacing, `Application` env for adapter/model
  allowlists, and the Oban queue topology. Each would need a tenant
  dimension under shared-schema multi-tenancy.
- The policy surface is already the hardest part of the codebase
  (14 trade-offs in `specs/security/known-trade-offs.md`, several
  policy-related). A `tenant_id` on every resource multiplies every
  policy check and every test matrix.
- The target user (BASELINE §3) is a small regulated-service org that
  self-hosts precisely because it does not want shared infrastructure.

## Options considered

### Option 1: Shared schema with `tenant_id`
- Pros: one instance serves many orgs; hosted-SaaS ready; cheapest ops
  per tenant.
- Cons: every resource, policy, index, audit topic, and background job
  needs tenant scoping; a single missed filter is a cross-tenant data
  leak in a regulated domain; contradicts the self-host positioning.

### Option 2: Postgres schema-per-tenant (Ash multitenancy `:context`)
- Pros: stronger isolation than Option 1; Ash has first-class support.
- Cons: migration fan-out, extension management per schema (pgvector,
  pg_trgm), Oban/queue partitioning complexity; still one BEAM node of
  blast radius; ops burden lands on the solo maintainer.

### Option 3: Keep single-tenant; one deployment = one instance (status quo)
- Pros: zero new attack surface; matches ADR-010/ADR-012 and the
  deployment-repo model; policy/test matrix stays as-is; "multi-tenancy"
  is achieved by running another instance.
- Cons: per-org infra cost; no hosted-SaaS story; fleet management (N
  instances) is the deployer's problem.

## Decision

We choose **Option 3: stay single-tenant through Season 2**.

Reasoning:

- In a safety-sensitive domain, cross-tenant leakage is the worst
  failure class available; the cheapest way to make it impossible is to
  not share state.
- No current user demand exists for shared infrastructure; the
  framework's positioning (self-host, deployment-as-configuration) is
  the differentiator.
- The revisit triggers below make this a reversible decision with an
  explicit re-entry point rather than an indefinite default.

Revisit triggers (any one reopens this ADR):

1. A concrete deployer needs ≥3 organizations on shared infrastructure.
2. A hosted-SaaS offering becomes a committed goal (not a possibility).
3. Ash multitenancy tooling matures to the point where schema-per-tenant
   costs less than one page of this ADR's Option 2 cons.

## Consequences

### Positive
- Season 2 planning can assume instance-global config, policies, and
  audit topics — no speculative tenant plumbing.
- The security review surface stays at its current (already large) size.

### Negative / accepted trade-offs
- If a hosted offering is ever committed, retrofitting tenancy will be
  a season-scale effort, not a story.

### Follow-up actions
- [ ] Mark the §13 checkbox in `specs/architecture.md` with this ADR.
- [ ] Re-evaluate at the Season 2 retrospective.

## References

- Related ADRs: ADR-010 (deployment as private repo), ADR-012 (single
  instance, multi-account workspace), ADR-018 (season structure)
