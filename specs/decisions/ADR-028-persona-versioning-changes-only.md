# ADR-028: Persona versioning stays paper-trail diffs; prompt provenance lives on Draft

**Status**: Proposed
**Date**: 2026-07-11
**Deciders**: solo maintainer (drafted at the Season 1 retrospective)

---

## Context

`specs/architecture.md §13` deferred to Phase 5: *"Persona versioning:
full snapshots or diffs?"* The underlying need is forensic: when a
draft is questioned later, we must reconstruct exactly what instruction
content produced it.

What Season 1 actually shipped:

- `Knowledge.Persona` (story 4.1) carries AshPaperTrail with
  `change_tracking_mode(:changes_only)` — versions record changed
  attributes per action (diffs), admin-only, sensitive fields redacted.
- `Draft.ai_prompt` (story 4.5) persists the **fully assembled prompt**
  — framework block, persona block (system_prompt + guardrail_notes as
  sent), conversation context, and since story 5.5 the retrieved
  knowledge block — verbatim, per generation attempt.
- `Manual` (story 5.1) adopted the same `:changes_only` paper-trail
  posture, and retrieval provenance pins `(manual_id, revision,
  position, content_hash)` per excerpt.

So the forensic question "what did the model see?" is already answered
by `Draft.ai_prompt` without consulting Persona versions at all.
Persona versions only need to answer "who changed the Persona, when,
and what changed" — an audit question, not a reconstruction question.

## Options considered

### Option 1: Switch paper-trail to full snapshots
- Pros: any historical Persona state readable from one row.
- Cons: duplicates multi-KB sensitive prompt text on every edit;
  redaction surface grows; adds nothing the Draft-side provenance does
  not already provide for the case that matters.

### Option 2: Snapshot only on generation (copy Persona fields onto Draft)
- Pros: explicit per-generation copy.
- Cons: already effectively true — the persona block inside
  `ai_prompt` *is* that copy; a second structured copy is redundant
  state to keep consistent.

### Option 3: Keep `:changes_only` diffs (status quo), name the invariant
- Pros: storage-lean; audit trail of who/when/what-changed intact;
  point-in-time state reconstructable by folding diffs when ever
  needed; generation forensics stay on `Draft.ai_prompt`.
- Cons: reconstructing a full historical Persona state takes a fold
  over versions rather than one read.

## Decision

We choose **Option 3: keep `:changes_only` diffs** and record the
invariant that makes it sufficient:

> **Generation-time instruction provenance is owned by
> `Draft.ai_prompt` (and `Draft.ai_retrieval` for knowledge), never by
> resource version history.** Any future change that stops persisting
> the assembled prompt verbatim must supersede this ADR first.

## Consequences

### Positive
- No migration, no storage growth, no new redaction surface.
- `Manual` and `Persona` stay on one uniform paper-trail posture.

### Negative / accepted trade-offs
- Rare "show me the whole Persona as of last March" asks require
  folding version diffs (acceptable: admin-side, infrequent).

### Follow-up actions
- [ ] Mark the §13 checkbox in `specs/architecture.md` with this ADR.

## References

- Related ADRs: ADR-016 (record chain), ADR-019 (soft-delete default),
  ADR-025 (AI adapter), ADR-026 (embedder boundary)
- Code: `lib/ashy_walnut_desk/knowledge/persona.ex` (paper_trail),
  `lib/ashy_walnut_desk/ai/jobs/generation_worker.ex` (ai_prompt persistence)
