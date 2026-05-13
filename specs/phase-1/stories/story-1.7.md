# Story 1.7: Property-based invariants for timeline and soft-delete

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2, 1.3, 1.4, 1.5, 1.6
**Status**: ready

---

## Goal

Add StreamData property tests for timeline ordering and soft-delete invariants required by Phase 1 architecture.

## Context

These invariants are explicitly called out in architecture §11 and should be validated separately from deterministic fixture tests.

## Reference specs

- `/AGENTS.md` §7.3 (audit and integrity expectations)
- `/specs/phase-1/requirements.md` §2 (AC7, AC10)
- `/specs/phase-1/architecture.md` §11 (Property-based test requirements)

## Acceptance criteria

- [ ] AC1: Property test proves mixed Event/Appointment/Note timeline output is monotonically non-decreasing by time field. — Verify: `mix test test/ashy_walnut_desk/identity/timeline_property_test.exs`
- [ ] AC2: Property test proves repeated archive operations remain idempotent and preserve soft-delete invariants. — Verify: `mix test test/ashy_walnut_desk/identity/soft_delete_property_test.exs`
- [ ] AC3: Property tests are deterministic in CI settings and pass inside `just verify`. — Verify: `just verify`

## Files to create

```
test/ashy_walnut_desk/identity/timeline_property_test.exs   — timeline ordering properties
test/ashy_walnut_desk/identity/soft_delete_property_test.exs   — soft-delete idempotence properties
```

## Files to modify

```
mix.exs   — add/confirm StreamData test dependency if needed
test/test_helper.exs   — property test support setup if needed
```

## Implementation notes

If StreamData dependency already exists, avoid unrelated test infra changes.

## Safety review

- Sensitive records touched? Indirectly via generated test fixtures only.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? Not the focus; invariant correctness focus.

## Out of scope (will NOT do in this story)

- LiveView UX screenshots: deferred to 1.9
- End-to-end integration flow: deferred to 1.10

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/identity/timeline_property_test.exs
mix test test/ashy_walnut_desk/identity/soft_delete_property_test.exs
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
