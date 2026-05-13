# Story 1.5: Note resource with ownership-aware editing

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2
**Status**: ready

---

## Goal

Implement the `Note` resource for operator observations with role-aware read/write behavior and owner-sensitive edit rules.

## Context

Notes complete the core Phase 1 Identity resource set and are required for timeline completeness.

## Reference specs

- `/AGENTS.md` §6 (resource/policy standards)
- `/specs/phase-1/requirements.md` §2 (AC2, AC3, AC7, AC8, AC9, AC10)
- `/specs/phase-1/architecture.md` §3.4 (`Note`)

## Acceptance criteria

- [ ] AC1: `Note` resource exists with `record_note`, `edit_note`, `archive`, `recover`, and filtered reads linked to Identity. — Verify: `mix test test/ashy_walnut_desk/identity/note_test.exs`
- [ ] AC2: Policy enforces viewer read-only and owner/admin edit semantics (self-edit or admin). — Verify: `mix test test/ashy_walnut_desk/identity/note_test.exs`
- [ ] AC3: Note audit/version behavior redacts sensitive values and restricts Version reads to admins. — Verify: `mix test test/ashy_walnut_desk/identity/note_test.exs`

## Files to create

```
lib/ashy_walnut_desk/identity/note.ex   — Note resource
lib/ashy_walnut_desk/identity/note/version_policies.ex   — Version policy mixin
test/ashy_walnut_desk/identity/note_test.exs   — Note unit tests
```

## Files to modify

```
lib/ashy_walnut_desk/identity.ex   — register Note resource
priv/repo/migrations/*   — generated migration(s)
priv/repo/resource_snapshots/*   — generated snapshots
```

## Implementation notes

Follow the same soft-delete and redaction conventions established in 1.2.

## Safety review

- Sensitive records touched? Yes — free-form operator note content.
- AI output to end user possible? No.
- Guardrails applied? Policy + redaction.
- Audit trail covered? Yes — Note paper trail.

## Out of scope (will NOT do in this story)

- Timeline UI behavior: deferred to 1.6
- Property-based timeline tests: deferred to 1.7

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/identity/note_test.exs
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
