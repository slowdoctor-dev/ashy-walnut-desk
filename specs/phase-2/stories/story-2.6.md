# Story 2.6: Hash-chained AuditEvent writer + verifier task

**Phase**: 2
**Estimate**: 4h
**Depends on**: 2.4, 2.5
**Status**: ready

---

## Goal

Implement `AuditEvent` hash-chain writes for each transition and ship `mix audit.verify` tamper-detection tooling.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (hash chain + verify task)
- `/specs/phase-2/architecture.md` §6.4, §11

## Acceptance criteria

- [ ] AC1: Chain transitions write immutable AuditEvents with `prev_hash` continuity within `chain_topic`. Payload follows the closed allow-list per `event_type` from architecture §3.8 ("Payload contract"); `ChainLink.canonicalize_payload/2` rejects unknown keys. — Verify: `mix test test/ashy_walnut_desk/interaction/audit_chain_test.exs`
- [ ] AC2: **Concurrent writes serialize correctly** (T2 review): using `Task.async_stream/3` with per-task Sandbox checkouts (`Ecto.Adapters.SQL.Sandbox.allow/3`), N parallel `Draft.approve+Action.execute` cycles on different drafts of the same chain all produce a continuous chain — every `prev_hash` resolves, walking from genesis reaches every event, no duplicate `prev_hash` values. — Verify: `mix test test/ashy_walnut_desk/interaction/audit_chain_concurrency_test.exs`
- [ ] AC3: `mix audit.verify` exits non-zero on tampering and zero on intact chain. — Verify: `mix test test/mix/tasks/audit_verify_test.exs`
- [ ] AC4: The `audit_events` composite indexes (`chain_topic + inserted_at`; `prev_hash`) are created in a migration with a timestamp >= the Ash-generated `audit_events` table migration. The full Phase 2 migration set applies cleanly via `mix ecto.migrate`. — Verify: `mix ecto.migrate && mix ecto.rollback` round-trip on a fresh DB

## Files to create

```
lib/ashy_walnut_desk/interaction/audit_chain.ex
lib/ashy_walnut_desk/interaction/changes/chain_link.ex
lib/mix/tasks/audit.verify.ex
test/ashy_walnut_desk/interaction/audit_chain_test.exs
test/ashy_walnut_desk/interaction/audit_chain_concurrency_test.exs
test/mix/tasks/audit_verify_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/inbox.ex
lib/ashy_walnut_desk/interaction/draft.ex
lib/ashy_walnut_desk/interaction/action.ex
lib/ashy_walnut_desk/interaction/compensation.ex
priv/repo/migrations/*phase_2*.exs
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/interaction/audit_chain_test.exs
mix test test/mix/tasks/audit_verify_test.exs
```
