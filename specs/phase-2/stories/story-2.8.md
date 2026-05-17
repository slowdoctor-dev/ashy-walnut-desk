# Story 2.8: Safety framing guard + audit coverage assertions

**Phase**: 2
**Estimate**: 2h
**Depends on**: 2.7
**Status**: ready

---

## Goal

Enforce “honest framing” and audit-trail coverage requirements with automated tests that fail on regressions.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (honest framing, audit coverage)
- `/specs/decisions/ADR-016-four-stage-record-chain.md`

## Acceptance criteria

- [ ] AC1: Test fails if forbidden “unsend” framing appears in LiveView templates/gettext strings. — Verify: `mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs`
- [ ] AC2: Approval/execution/status transitions produce expected PaperTrail version records. — Verify: `mix test test/ashy_walnut_desk/interaction/paper_trail_coverage_test.exs`
- [ ] AC3: Conversation create is denied when Identity is soft-deleted (regression guard at acceptance layer). — Verify: `mix test test/ashy_walnut_desk/interaction/conversation_test.exs`

## Files to create

```
test/ashy_walnut_desk_web/safety/honest_framing_test.exs
test/ashy_walnut_desk/interaction/paper_trail_coverage_test.exs
```

## Files to modify

```
priv/gettext/*.po
lib/ashy_walnut_desk_web/live/inbox_live/*.ex
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs
mix test test/ashy_walnut_desk/interaction/paper_trail_coverage_test.exs
```
