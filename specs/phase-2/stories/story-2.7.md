# Story 2.7: Operator LiveView flow for Inbox-to-Action chain

**Phase**: 2
**Estimate**: 3h
**Depends on**: 2.5, 2.6
**Status**: done

---

## Goal

Deliver the operator-facing LiveView flow for creating Inbox, composing/approving draft, countdown UX, and chain visualization.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (operator UX evidence)
- `/specs/phase-2/architecture.md` §4

## Acceptance criteria

- [x] AC1: Authenticated operator can open Inbox for an Identity and view chain state progression in one UI flow. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/index_test.exs`
- [x] AC2: Draft compose/revise/approve flow works with server-side enforcement path and visible countdown state. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/show_test.exs`
- [x] AC3: Chain visualization component renders four stages without “unsend” framing language. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/chain_component_test.exs`
- [x] AC4: Viewer role cannot reach write actions from UI. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/authorization_test.exs`

## Files to create

```
lib/ashy_walnut_desk_web/live/inbox_live/index.ex
lib/ashy_walnut_desk_web/live/inbox_live/show.ex
lib/ashy_walnut_desk_web/live/inbox_live/new.ex
lib/ashy_walnut_desk_web/live/inbox_live/chain_component.ex
lib/ashy_walnut_desk_web/components/countdown_send_button.ex
test/ashy_walnut_desk_web/live/inbox_live/index_test.exs
test/ashy_walnut_desk_web/live/inbox_live/show_test.exs
test/ashy_walnut_desk_web/live/inbox_live/chain_component_test.exs
test/ashy_walnut_desk_web/live/inbox_live/authorization_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex
lib/ashy_walnut_desk_web/live_user_auth.ex
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/live/inbox_live/index_test.exs
mix test test/ashy_walnut_desk_web/live/inbox_live/show_test.exs
```
