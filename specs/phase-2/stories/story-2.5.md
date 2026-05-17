# Story 2.5: Chain transition actions + server countdown enforcement

**Phase**: 2
**Estimate**: 3h
**Depends on**: 2.3, 2.4
**Status**: done

---

## Goal

Implement the operational chain transitions (`Inbox -> Draft -> Action -> Compensation`) with server-authoritative 5-second countdown and approver attribution.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (AC for chain order, countdown, approver id)
- `/specs/phase-2/architecture.md` §6
- `/specs/decisions/ADR-013-five-second-countdown.md`

## Acceptance criteria

- [ ] AC1: `Draft.approve` records approval metadata and registers Compensation in the same transaction. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_approval_test.exs`
- [ ] AC2: `Action.execute` is rejected if approval is newer than 5 seconds (direct action bypass blocked). The `CountdownGuard` is a `before_action` change performing a server-authoritative elapsed-time check against `draft.approved_at`. — Verify: `mix test test/ashy_walnut_desk/interaction/countdown_guard_test.exs`
- [ ] AC3: Successful execute path records outbound Message with non-null `approved_by_id` and marks Inbox executed. — Verify: `mix test test/ashy_walnut_desk/interaction/action_execute_test.exs`
- [ ] AC4: Stub adapter path reaches `Action.status: :executed` without external API dependency. — Verify: `mix test test/ashy_walnut_desk/interaction/action_execute_test.exs`
- [ ] AC5: **Concurrent approval race is blocked** (S3 review): two simultaneous `Draft.approve` calls on the same draft serialize via row-level lock. The first succeeds; the second returns `{:error, :draft_not_drafting}` with no Compensation written, no Action created, no extra AuditEvent. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_approval_concurrency_test.exs` (Task.async_stream with two Sandbox checkouts; assert exactly one approved/compensation/action pair and one `:draft_not_drafting` error)
- [ ] AC6: `Draft.approve` validates `compensation_body` is non-null at approval time per ADR-016, even though the field is optional at `compose_draft`. — Verify: covered by `draft_approval_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/changes/countdown_guard.ex
lib/ashy_walnut_desk/interaction/changes/compensation_at_approval.ex
test/ashy_walnut_desk/interaction/draft_approval_test.exs
test/ashy_walnut_desk/interaction/draft_approval_concurrency_test.exs
test/ashy_walnut_desk/interaction/countdown_guard_test.exs
test/ashy_walnut_desk/interaction/action_execute_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/draft.ex
lib/ashy_walnut_desk/interaction/action.ex
lib/ashy_walnut_desk/interaction/inbox.ex
lib/ashy_walnut_desk/interaction/message.ex
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/interaction/draft_approval_test.exs
mix test test/ashy_walnut_desk/interaction/countdown_guard_test.exs
mix test test/ashy_walnut_desk/interaction/action_execute_test.exs
```
