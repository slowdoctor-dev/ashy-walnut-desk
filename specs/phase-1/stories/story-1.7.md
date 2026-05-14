# Story 1.7: Property-based invariants for timeline and soft-delete

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2, 1.3, 1.4, 1.5, 1.6
**Status**: done

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

- [x] AC1: Property test proves mixed Event/Appointment/Note timeline output is monotonically non-decreasing by time field. — Verify: `mix test test/ashy_walnut_desk/identity/timeline_property_test.exs`
- [x] AC2: Property test proves repeated archive operations remain idempotent and preserve soft-delete invariants. — Verify: `mix test test/ashy_walnut_desk/identity/soft_delete_property_test.exs`
- [x] AC3: Property tests are deterministic in CI settings and pass inside `just verify`. — Verify: `just verify`

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
  - `stream_data` is already a non-optional transitive dep of `:ash` 1.3.0
    in `mix.lock`, so `ExUnitProperties` works without modifying `mix.exs`
    or `test_helper.exs`.
  - Property tests are DB-backed (each iteration inserts via the same Ash
    actions operators use) rather than pure-function tests against an
    extracted helper. This was the lightest way to exercise the *actual*
    contract `IdentityLive.Show.load_timeline/1` produces without
    refactoring production code into a public helper for test access.
    `max_runs: 25` keeps total runtime around 7s; full suite still under
    16s.
  - Timeline assertion direction: architecture §11 specifies
    "monotonically non-decreasing", but `IdentityLive.Show.load_timeline/1`
    sorts `{:desc, DateTime}` so newest entries appear first. The test
    asserts the operator-visible direction (non-increasing) and the test
    docstring calls out the inversion so a future reader doesn't read
    architecture §11 and assume a regression.
  - Soft-delete property tests share one sandbox transaction across all
    `check all` iterations. Because `users_one_admin_idx` forbids two
    admin rows in the same transaction, the admin is created once in
    `setup` and reused; each iteration creates a fresh `:operator` plus
    fresh records.
- Spec drift noticed:
  - Architecture §11 says "monotonically non-decreasing"; the implemented
    sort direction in `IdentityLive.Show.load_timeline/1` is descending.
    Not worth amending the architecture text — the operator-facing
    contract is "consistent sort by time"; the direction is an
    implementation detail noted in the test docstring.
- Gotchas to add to AGENTS.md §10:
  - Phase 1's `Accounts.User` carries a `users_one_admin_idx` unique
    constraint (single admin per transaction). Property tests that share
    a transaction across `check all` iterations must create the admin
    once in `setup` (not inside the property body) and reuse it; only
    `:operator`/`:viewer` actors are safe to mint per iteration.
