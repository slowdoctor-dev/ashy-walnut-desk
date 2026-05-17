# Story 2.10: Phase 2 integration gate (full AC verification)

**Phase**: 2
**Estimate**: 3h
**Depends on**: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9
**Status**: ready

---

## Goal

Run and codify the final integration checks proving all Phase 2 acceptance criteria are satisfied together.

## Context

This is the mandatory final integration story for the phase.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (all phase ACs)
- `/specs/phase-2/architecture.md` §11

## Acceptance criteria

- [ ] AC1: LiveView E2E test covers complete open-inbox -> compose-draft -> approve/countdown -> executed/action+compensation flow with stub adapter. — Verify: `mix test test/ashy_walnut_desk_web/live/phase2_e2e_test.exs`
- [ ] AC2: Property tests validate single-writer chain invariants (`Action`↔`Compensation` bijection; payload canonicalization deterministic). The concurrency property — chain continuity under load — is owned by story 2.6's `audit_chain_concurrency_test.exs` and is referenced (not duplicated) here. — Verify: `mix test test/ashy_walnut_desk/interaction/properties/chain_invariants_test.exs && mix test test/ashy_walnut_desk/interaction/audit_chain_concurrency_test.exs`
- [ ] AC3: `mix audit.verify` is integrated into project verification workflow and passes on intact DB state. — Verify: `just verify`
- [ ] AC4: `specs/phase-2/requirements.md` phase-level checklist is updated to reflect implemented acceptance outcomes. — Verify: manual review + `rg -n "\[x\]|\[ \]" specs/phase-2/requirements.md`
- [ ] AC5: **Cross-link integration test** (R2-2 review): `Conversation.open_conversation` with a soft-deleted `identity_id` returns `{:error, _}` and writes no Conversation row. Phase 2's first cross-axis link (Identity → Conversation) must not allow zombie references. — Verify: `mix test test/ashy_walnut_desk_web/live/phase2_e2e_test.exs` (asserts the soft-deleted-Identity denial path; same test file as AC1, separate `describe` block)
- [ ] AC6: **Honest-framing guard** (ADR-016) — references the test asserted by story 2.8 AC1 (`test/ashy_walnut_desk_web/safety/honest_framing_test.exs`). Story 2.10 does not duplicate the grep mechanics; it asserts the test exists and runs as part of `just verify`. — Verify: `mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs` and confirm it runs in the `mix test` portion of `just verify`.

## Files to create

```
test/ashy_walnut_desk_web/live/phase2_e2e_test.exs
test/ashy_walnut_desk/interaction/properties/chain_invariants_test.exs
```

## Files to modify

```
justfile
specs/phase-2/requirements.md
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/live/phase2_e2e_test.exs
mix test test/ashy_walnut_desk/interaction/properties/chain_invariants_test.exs
```
