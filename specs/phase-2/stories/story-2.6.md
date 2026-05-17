# Story 2.6: Hash-chained AuditEvent writer + verifier task

**Phase**: 2
**Estimate**: 3h
**Depends on**: 2.4, 2.5
**Status**: ready

---

## Goal

Implement `AuditEvent` hash-chain writes for each transition and ship `mix audit.verify` tamper-detection tooling.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (hash chain + verify task)
- `/specs/phase-2/architecture.md` §6.4, §11

## Acceptance criteria

- [ ] AC1: Chain transitions write immutable AuditEvents with `prev_hash` continuity within `chain_topic`. — Verify: `mix test test/ashy_walnut_desk/interaction/audit_chain_test.exs`
- [ ] AC2: Concurrent transition writes serialize correctly and preserve continuity. — Verify: `mix test test/ashy_walnut_desk/interaction/audit_chain_concurrency_test.exs`
- [ ] AC3: `mix audit.verify` exits non-zero on tampering and zero on intact chain. — Verify: `mix test test/mix/tasks/audit_verify_test.exs`
- [ ] AC4: Architect migration-order ambiguity is resolved: index creation for `audit_events` must run after table exists (same migration or later timestamp), never before table creation. — Verify: migration set applies cleanly via `mix ecto.migrate`

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
