# ADR-020: Consent is an append-only ledger, not a row-with-history

**Status**: Accepted
**Date**: 2026-05-13
**Deciders**: Phase 1 user + Architect (Claude Opus 4.7).

---

## Context

Consent is the most legally-sensitive record in the Identity axis. A
single misrepresentation of "did this customer consent at time T?" can
cost a deployer in regulated industries (healthcare, legal, financial)
more than the rest of the system put together.

Two natural ways to model consent in Ash + Postgres:

1. One row per (identity, consent_type), updated when consent changes;
   audit via `AshPaperTrail` writes a Version row for each change.
2. Append-only ledger: each consent decision creates a new immutable
   row; "current consent" is a query over the ledger.

Phase 1 requirements §7 asked which; the resolved answer is (2).

This ADR records why and turns it into a project-wide pattern available
to other legally-sensitive records that might arrive in future phases
(e.g. compliance attestations, regulatory disclosures, formal
acknowledgements).

## Options considered

### Option 1: Update-in-place + AshPaperTrail

- Pros:
  - Mirrors Phase 0's `User` pattern (single row + Version trail).
  - Simpler schema: one row per (identity, type), one query for current
    state.
  - Familiar UX in the LiveView: an Edit button on the consent record.
- Cons:
  - The Version resource is a separate, auto-generated module. Its
    correctness depends on AshPaperTrail's redaction config, the
    Version policy mixin, and the `change_tracking_mode` setting all
    being right simultaneously. Phase 0's `[0.fix]` hardening pass
    found a real plaintext leak via exactly this surface (commit
    `0cd7796`).
  - The "current consent" reflects the live row; reconstructing
    historic consent requires walking the Version table, which is
    fragile if AshPaperTrail config drifts.
  - Hard-deleting a Version row (via DB access, a future migration,
    etc.) silently destroys legal evidence.

### Option 2: Append-only ledger

- Pros:
  - The audit trail **is** the data. No separate Version mechanism to
    drift, no redaction policy to misconfigure for the historic record
    (sensitive notes still get `sensitive? true`, but that's about
    runtime exposure, not historic reconstruction).
  - "What was consent on date X?" is one SQL query against a single
    table.
  - Immutability is enforced by the absence of an Update action.
  - The Consent resource never needs `AshPaperTrail` — fewer moving
    parts.
- Cons:
  - "Current consent" needs a query function (`current_consent/2`),
    not a column read. Slightly more work in the UI.
  - The ledger grows monotonically. For Phase 0-scale usage this is
    invisible; for very high-frequency consent flips, an index on
    `(identity_id, consent_type, effective_at DESC)` is needed.
  - Requires a sentinel for "no consent ever recorded" — handled by
    the query returning `nil` when no rows exist.

### Option 3: Defer to Architect's call

- This was offered to the user and they chose Option 2 explicitly. The
  Architect's call here is to formalize the pattern.

## Decision

We chose **Option 2: append-only ledger, project-wide pattern for
legally-sensitive records**.

Reasoning:

- The audit-trail-is-the-data property removes a class of subtle bugs
  (the same class the `[0.fix]` Phase 0 hardening pass had to chase
  down).
- Immutability is enforced structurally (no Update action) rather than
  by policy. Structural enforcement beats policy enforcement for
  invariants we care about deeply.
- The query-vs-column cost is small and one-time. The
  `current_consent/2` function lives on the `AshyWalnutDesk.Identity`
  domain and is used by the Show LiveView + tests.
- The pattern generalizes: any future record where "what was true at
  time T" matters more than "what is the current state" should use the
  same shape. Compliance attestations, regulatory disclosures, formal
  acknowledgements — all good candidates.

## Consequences

### Positive

- Consent gets a structurally-enforced immutability invariant, not a
  policy-enforced one.
- Historic reconstruction is one query, no PaperTrail dependency.
- The pattern is reusable for future legally-sensitive records.
- No interaction with the soft-delete pattern (ADR-019) — explicit
  exception called out in ADR-019's Consequences.

### Negative / accepted trade-offs

- Slight extra work in the LiveView: "show current consent" calls the
  query function rather than reading a column.
- Ledger growth is unbounded within the framework. The framework's
  position is that consent rows are too important to purge; deployer
  retention policies must decide separately if/when to archive
  historic ledger rows (e.g., into cold storage). This framework will
  not ship a purge.
- Tooling around `AshPaperTrail` doesn't apply to Consent. Tests
  asserting "this resource is audited" need to special-case Consent
  (the audit is the table, not a Version row).

### Follow-up actions

- [ ] When Phase 2+ ships another legally-sensitive record, decide
      whether to use this pattern by default or to argue for an
      exception.
- [ ] If high-frequency consent flips ever appear in a deployer's data,
      revisit the index strategy. Today's single-axis composite index
      is enough.

## References

- Related ADRs: ADR-016 (four-stage record chain — Consent ledger is a
  natural fit), ADR-019 (soft-delete default — Consent is the explicit
  exception).
- AGENTS.md §7.3 (audit mandatory).
- `specs/phase-1/requirements.md` §2 (consent AC), §7 (resolved Q2).
- `specs/phase-1/architecture.md` §3.6 (Consent resource shape).
