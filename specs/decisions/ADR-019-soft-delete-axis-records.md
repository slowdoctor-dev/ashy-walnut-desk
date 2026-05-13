# ADR-019: Soft-delete is the default for axis records

**Status**: Accepted
**Date**: 2026-05-13
**Deciders**: Phase 1 user + Architect (Claude Opus 4.7) with input from Codex (Analyst persona).

---

## Context

Phase 1 introduces the Identity axis. The six new resources (Identity,
Event, Appointment, FollowUp, Note, Consent) all touch customer-facing
data. AGENTS.md §7.3 makes audit trails mandatory for every state
transition; AGENTS.md §7.4 forbids "raw sensitive content [being] logged
in production." Project architecture §8 lists invariants that depend on
records remaining linkable across the audit chain (ADR-016).

These constraints make hard-deleting customer records a footgun: the
moment a row is `DELETE FROM identities WHERE id = $1`, the audit trail
loses the actual data, related rows either become orphaned or cascade-
delete in surprising ways, and a future regulator asking "what did this
customer's record contain on date X" can't be answered.

Phase 1's requirements §7 asked whether to include soft-delete; the
answer is yes (TO-resolved 2026-05-13).

The choice is now whether this is a Phase-1-only convention or a
project-wide one. The same arguments will apply to Phase 2 (Interaction:
Conversation, Message) and Phase 5 (Knowledge: Manual, Persona).

## Options considered

### Option 1: Soft-delete only, project-wide convention

- Pros:
  - Audit chain stays intact; ADR-016 holds across all axes.
  - Recovery is possible; a misclicked archive doesn't lose data.
  - Cross-resource ownership (FK with `ON DELETE RESTRICT`) becomes
    enforceable across the project, not just Phase 1.
  - Aligns with AGENTS.md §7.3 without case-by-case re-arguing.
- Cons:
  - Tables grow monotonically. Need a separate "purge after retention
    window" mechanism (deployer-config; out of scope for the framework).
  - Every read action needs a default filter on `deleted_at`. Easy to
    forget. Mitigated by a shared `SoftDelete` change + a code-review
    checklist + tests that assert default reads exclude archived rows.

### Option 2: Soft-delete in Phase 1 only, decide per-phase later

- Pros: lowest commitment.
- Cons: every future phase re-litigates the same question. Specs drift
  as conventions diverge. The "Identity is soft-delete but Conversation
  is hard-delete" inconsistency is worse than picking one.

### Option 3: Hard-delete allowed, audited via PaperTrail

- Pros: simplest schema.
- Cons: AshPaperTrail records the deletion event but not the row's
  values (sensitive_attributes redaction). The audit chain loses the
  data we'd most need. Cross-resource ownership becomes meaningless
  if parent rows can vanish. Conflicts with ADR-016.

## Decision

We chose **Option 1: soft-delete as the project-wide default for axis
records**.

Reasoning:

- Phase 1's six new resources all warrant it independently; making it a
  convention costs no more than making it a Phase-1 rule.
- ADR-016's four-stage record chain depends on rows staying around. A
  project-wide soft-delete rule prevents future phases from accidentally
  breaking that.
- The implementation is a tiny, shared `Ash.Resource.Change` module
  (`Identity.Changes.SoftDelete`) plus a per-resource convention; not a
  framework-level invention.
- Exception is allowed for resources where soft-delete is incoherent —
  e.g., immutable append-only ledgers, where a "revoked" state is a new
  row rather than a state change. Phase 1 ships no such resource;
  Phase 4's Consent (when it lands) is the expected first case and
  will need its own ADR. Each future exception must justify itself.

## Consequences

### Positive

- Audit trail stays complete across all axes.
- "Recover an archived record" is a uniform operator UX across the app.
- Cross-resource FK with `ON DELETE RESTRICT` becomes a project-wide
  defense-in-depth pattern.
- The pattern itself is simple: `deleted_at` attribute + default-filter
  read + `archive`/`recover` actions + `SoftDelete` change.

### Negative / accepted trade-offs

- Tables grow without a built-in retention sweep. Each deployer is
  responsible for defining a retention window and running a periodic
  hard-purge job in their deployment instance (per ADR-010). The
  framework will not ship that purge.
- Every resource using this pattern must explicitly add the
  `deleted_at` attribute and the default filter. Forgetting either
  silently breaks the invariant. Mitigated by tests and by surfacing
  it in `prompts/bmad-architect.md` as a checklist item for future
  axes.
- `read_with_archived` (admin-only) is a footgun if it appears in
  policy gaps. Mitigated by making it explicit in each resource and
  including the policy in standard test scaffolding.

### Follow-up actions

- [ ] Architects of Phase 2, 3, 5 must call out any resource that
      legitimately needs to be exempt (e.g., transient `Draft` rows
      might be hard-deletable after send completion).
- [ ] Deployer onboarding docs (out of scope for this framework repo)
      must mention the retention-and-purge responsibility.

## References

- Related ADRs: ADR-016 (four-stage record chain).
- AGENTS.md §7.3 (audit mandatory), §7.4 (no raw sensitive content
  logged).
- `specs/phase-1/requirements.md` §2 (soft-delete AC), §7 (resolved
  Q1).
- `specs/phase-1/architecture.md` §3.5 (Consent deferred — first
  expected exception to this ADR; ADR for it written when Consent
  has a real consumer).
