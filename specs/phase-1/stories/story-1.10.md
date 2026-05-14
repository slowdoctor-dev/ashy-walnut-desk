# Story 1.10: Phase 1 Identity-axis integration test gate

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9
**Status**: done

---

## Goal

Add a single end-to-end integration test that validates Phase 1 Identity-axis composition (create identity, link records, timeline visibility, role boundaries, archive/recover behavior) and confirms phase acceptance criteria are met together.

## Context

Per BMAD PM rules, the final story is the phase integration gate that catches cross-resource regressions beyond unit-level coverage.

## Reference specs

- `/AGENTS.md` §8 (GSD verify gate)
- `/specs/phase-1/requirements.md` §2 (phase ACs)
- `/specs/phase-1/architecture.md` §11 (integration strategy)

## Acceptance criteria

- [x] AC1: Integration test (`Phoenix.LiveViewTest`) executes create identity → record event → schedule follow-up appointment (with originating event) → record note → render timeline assertions in one authenticated flow. — Verify: `mix test test/integration/identity_phase1_e2e_test.exs`
- [x] AC2: Same integration suite asserts role boundaries (`:viewer` read-only, non-admin cannot recover archived identity, admin can recover). — Verify: `mix test test/integration/identity_phase1_e2e_test.exs`
- [x] AC3: Phase-level verification remains green with integration gate included. — Verify: `just verify`

## Files to create

```
test/integration/identity_phase1_e2e_test.exs   — cross-resource Phase 1 integration gate
```

## Files to modify

```
specs/phase-1/requirements.md   — (optional) update checklist statuses when phase is complete
```

## Implementation notes

Keep fixture data fake and deterministic; avoid duplicating detailed unit assertions already covered in earlier stories.

## Safety review

- Sensitive records touched? Yes — full identity record flow with linked records.
- AI output to end user possible? No.
- Guardrails applied? Policy boundaries and soft-delete constraints.
- Audit trail covered? Indirectly via actions exercised; explicit audit assertions remain in unit stories.

## Out of scope (will NOT do in this story)

- Additional resource types beyond Identity/Event/Appointment/Note: deferred to later phases
- Performance/load characteristics of timeline queries: deferred to later phase

## Verification

```bash
just verify
mix test test/integration/identity_phase1_e2e_test.exs
```

## Notes during implementation

- Decisions made:
  - Two-test layout in a single file (`AC1` composition + `AC2` role boundaries) instead of one mega-test. Each test reads top-to-bottom as an integration story and a failure points cleanly at one concern. The story explicitly requires a single file; it does not require a single test.
  - The Show LV's `appointment_form` does not expose `originating_event_id` (Phase 1 deferred a full follow-up linker UI). The follow-up appointment is therefore created through `Ash.create(..., action: :schedule_appointment, actor: operator)` — the same action the LV would call — to exercise the originating-event link without inventing a UI for it.
  - `:operator` in AC2 is minted via direct `Ash.create(User, ..., authorize?: false)` (no magic-link) because the operator only exercises Ash actions (archive + recover-denied). This avoids a third magic-link round-trip and the `AssignFirstUserAdmin` role-clobber dance for a user that never mounts a LiveView.
- Spec drift noticed: none. AC1/AC2/AC3 hold as written.
- Gotchas to add to AGENTS.md §10: none new. The existing magic-link/role-clobber and form-prefix-collision gotchas already cover the integration-test surface; the new test reuses the documented mitigations.
