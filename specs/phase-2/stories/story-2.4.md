# Story 2.4: Immutable chain resources + adapter contract

**Phase**: 2
**Estimate**: 2h
**Depends on**: 2.2
**Status**: ready

---

## Goal

Implement immutable resources (`Action`, `Compensation`, `AuditEvent`) and define `Channel.Adapter` + stub adapter contract.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (four-stage chain, immutable resources, stub adapter)
- `/specs/phase-2/architecture.md` §3.6–§3.8, §5

## Acceptance criteria

- [ ] AC1: `Action`, `Compensation`, and `AuditEvent` expose no soft-delete/destroy path and enforce immutable record intent. — Verify: `mix test test/ashy_walnut_desk/interaction/immutability_test.exs`
- [ ] AC2: `Channel.Adapter` behaviour and `Adapters.Stub` compile and return deterministic no-op payload. — Verify: `mix test test/ashy_walnut_desk/interaction/adapter_stub_test.exs`
- [ ] AC3: Resource relationships are present (`Action`→`Draft`, `Compensation`→`Action`, `AuditEvent` chain-topic model). — Verify: `mix test test/ashy_walnut_desk/interaction/chain_schema_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/adapter.ex
lib/ashy_walnut_desk/interaction/adapters/stub.ex
test/ashy_walnut_desk/interaction/immutability_test.exs
test/ashy_walnut_desk/interaction/adapter_stub_test.exs
test/ashy_walnut_desk/interaction/chain_schema_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/action.ex
lib/ashy_walnut_desk/interaction/compensation.ex
lib/ashy_walnut_desk/interaction/audit_event.ex
```

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/interaction/immutability_test.exs
mix test test/ashy_walnut_desk/interaction/adapter_stub_test.exs
```
