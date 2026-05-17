# Story 2.3: Mutable Interaction resources + soft-delete policies

**Phase**: 2
**Estimate**: 3h
**Depends on**: 2.2
**Status**: ready

---

## Goal

Implement mutable Interaction resources (`Conversation`, `Message`, `Channel`, `Inbox`, `Draft`) with ADR-019 soft-delete behavior, authorization rules, and core invariants.

## Reference specs

- `/AGENTS.md` §6, §7
- `/specs/phase-2/requirements.md` §2 (Conversation/Message invariants, soft-delete scope)
- `/specs/phase-2/architecture.md` §3.1–§3.5

## Acceptance criteria

- [ ] AC1: `Conversation` enforces exactly one `Identity` + one `Channel`, and denies creation for soft-deleted Identity. — Verify: `mix test test/ashy_walnut_desk/interaction/conversation_test.exs`
- [ ] AC2: `Message` enforces exactly one `Conversation`; outbound shape requires approver attribution path (direct bypass rejected). — Verify: `mix test test/ashy_walnut_desk/interaction/message_test.exs`
- [ ] AC3: `Conversation`, `Message`, `Inbox`, `Draft` implement archive/recover/read_with_archived soft-delete pattern; `Channel` follows configured mutable policy path. — Verify: `mix test test/ashy_walnut_desk/interaction/soft_delete_test.exs`
- [ ] AC4: Sensitive fields are marked and PaperTrail mixin is present where required. — Verify: `mix test test/ashy_walnut_desk/interaction/audit_redaction_test.exs`

## Files to create

```
test/ashy_walnut_desk/interaction/conversation_test.exs
test/ashy_walnut_desk/interaction/message_test.exs
test/ashy_walnut_desk/interaction/soft_delete_test.exs
test/ashy_walnut_desk/interaction/audit_redaction_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/conversation.ex
lib/ashy_walnut_desk/interaction/message.ex
lib/ashy_walnut_desk/interaction/channel.ex
lib/ashy_walnut_desk/interaction/inbox.ex
lib/ashy_walnut_desk/interaction/draft.ex
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/interaction/conversation_test.exs
mix test test/ashy_walnut_desk/interaction/message_test.exs
mix test test/ashy_walnut_desk/interaction/soft_delete_test.exs
```
