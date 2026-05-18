# Story 3.2: Adapter Boundary Hardening + Contract Conformance Suite

**Phase**: 3
**Estimate**: 3h
**Depends on**: 3.1
**Status**: planned

---

## Goal

Harden `Interaction.Adapter` as the sole extension point and add conformance tests proving Twilio and a test-only Echo adapter satisfy the same contract.

## Context

Phase 3 must ship Twilio while preserving future extensibility: later providers should land without touching Twilio code, `Action.execute`, or Compensation actions. This story defines and locks that contract at requirements-test level.

## Reference specs

- `/AGENTS.md` §6 Naming + standards
- `/specs/architecture.md` §9 Channel adapters
- `/specs/phase-3/architecture.md` §1 Overview, §3.5 Action, §12 Q4/Q5
- `/specs/decisions/ADR-022-twilio-as-first-real-adapter.md`

## Acceptance criteria

- [ ] AC1: `Interaction.Adapter` behavior contract is explicit for inbound + outbound paths and used by both Twilio and Echo implementations. — Verify: `mix test test/ashy_walnut_desk/interaction/adapters/adapter_contract_test.exs`
- [ ] AC2: A test-only `Interaction.Adapters.Echo` fixture exists and passes the same contract tests as Twilio. — Verify: `mix test test/ashy_walnut_desk/interaction/adapters/adapter_contract_test.exs --trace`
- [ ] AC3: Contract tests assert extension-point isolation: adding a provider module + allowlist entry does not require edits to Twilio adapter module, `Interaction.Action`, or `Interaction.Compensation` resource action definitions. — Verify: `mix test test/ashy_walnut_desk/interaction/adapters/adapter_extension_isolation_test.exs`
- [ ] AC4: Provider allowlist includes Twilio and can admit additional adapters by configuration only. — Verify: `mix test test/ashy_walnut_desk/interaction/adapter_allowed_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/adapters/echo.ex                       — test-only adapter fixture implementation

test/ashy_walnut_desk/interaction/adapters/adapter_contract_test.exs    — shared conformance contract tests

test/ashy_walnut_desk/interaction/adapters/adapter_extension_isolation_test.exs  — isolation/no-core-modification assertions
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/adapter.ex                             — finalize behavior contract surface
lib/ashy_walnut_desk/interaction/adapters/twilio.ex                     — ensure Twilio conforms to finalized contract
config/config.exs                                                       — adapter allowlist baseline includes Twilio
```

## Implementation notes

Keep this story focused on boundary and tests. Do not add webhook routing, intake policy, or outbound retry logic here beyond what is required for contract shape.

## Safety review

- Sensitive records touched? no
- AI output to end user possible? no
- Guardrails applied? N/A
- Audit trail covered? N/A (contract story)

## Out of scope (will NOT do in this story)

- Webhook signature verification and inbound record creation: deferred to story 3.3
- Idempotency/replay persistence and contracts: deferred to story 3.4
- Oban retry workflow for outbound execution: deferred to story 3.5

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/interaction/adapters/adapter_contract_test.exs
mix test test/ashy_walnut_desk/interaction/adapters/adapter_extension_isolation_test.exs
mix test test/ashy_walnut_desk/interaction/adapter_allowed_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
