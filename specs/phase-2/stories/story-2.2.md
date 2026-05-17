# Story 2.2: Interaction domain bootstrap + resource skeletons

**Phase**: 2
**Estimate**: 2h
**Depends on**: 2.1
**Status**: ready

---

## Goal

Create the Interaction domain and compile-safe resource skeleton modules for all Phase 2 entities, with no workflow logic yet.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (resource list AC)
- `/specs/phase-2/architecture.md` §2–§3

## Acceptance criteria

- [ ] AC1: `AshyWalnutDesk.Interaction` domain exists and is wired in app domain configuration. — Verify: `mix compile`
- [ ] AC2: Resource modules exist for `Conversation`, `Message`, `Channel`, `Inbox`, `Draft`, `Action`, `Compensation`, `AuditEvent`. — Verify: `rg -n "defmodule AshyWalnutDesk\.Interaction\.(Conversation|Message|Channel|Inbox|Draft|Action|Compensation|AuditEvent)" lib/ashy_walnut_desk/interaction`
- [ ] AC3: Resources declare explicit actions and policy sections (no public-by-default behavior). — Verify: `mix test test/ashy_walnut_desk/interaction/policy_shape_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/interaction.ex
lib/ashy_walnut_desk/interaction/conversation.ex
lib/ashy_walnut_desk/interaction/message.ex
lib/ashy_walnut_desk/interaction/channel.ex
lib/ashy_walnut_desk/interaction/inbox.ex
lib/ashy_walnut_desk/interaction/draft.ex
lib/ashy_walnut_desk/interaction/action.ex
lib/ashy_walnut_desk/interaction/compensation.ex
lib/ashy_walnut_desk/interaction/audit_event.ex
test/ashy_walnut_desk/interaction/policy_shape_test.exs
```

## Files to modify

```
config/config.exs
lib/ashy_walnut_desk.ex
```

## Verification

```bash
just verify
mix compile
mix test test/ashy_walnut_desk/interaction/policy_shape_test.exs
```
