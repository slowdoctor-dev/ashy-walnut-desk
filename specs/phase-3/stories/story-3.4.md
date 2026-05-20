# Story 3.4: Idempotency + Replay Controls (Inbound and Outbound)

**Phase**: 3
**Estimate**: 2h
**Depends on**: 3.2, 3.3
**Status**: done

---

## Goal

Add deterministic replay protection and idempotency contracts for both inbound webhook deliveries and outbound action execution keys.

## Context

Phase 3 must be retry-safe and replay-safe before outbound retry jobs are enabled. This story defines and enforces dedupe boundaries that later outbound worker logic depends on.

## Reference specs

- `/AGENTS.md` §7.3 Audit trail mandatory
- `/specs/architecture.md` §8 Data invariants, §10 Failure modes
- `/specs/phase-3/architecture.md` §3.1 InboundDelivery, §3.5 Action, §12 Q4/Q5
- `/specs/decisions/ADR-023-oban-for-outbound-retry.md`
- `/specs/decisions/ADR-024-inbound-intake-policy.md`

## Acceptance criteria

- [ ] AC1: Inbound replay dedupe persists by provider message id (`provider`, `provider_message_id`) and prevents duplicate business-record creation on webhook replay. — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_delivery_dedupe_test.exs`
- [ ] AC2: Outbound action idempotency key is deterministic per `action_id` (or equivalent one-to-one key) and remains stable across retries. — Verify: `mix test test/ashy_walnut_desk/interaction/outbound_idempotency_key_test.exs`
- [ ] AC3: Duplicate inbound/outbound replay attempts are auditable with deterministic outcomes (`processed`/`duplicate`/`failed_intake` or equivalent). — Verify: `mix test test/ashy_walnut_desk/interaction/replay_audit_outcome_test.exs`
- [ ] AC4: Dedupe retention policy for inbound replay ledger is encoded and test-covered (TTL/expunge path). — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_delivery_retention_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/inbound_delivery.ex                                — inbound dedupe ledger resource
lib/ashy_walnut_desk/interaction/changes/outbound_idempotency.ex                    — deterministic outbound key stamping

test/ashy_walnut_desk/interaction/inbound_delivery_dedupe_test.exs                  — inbound replay dedupe tests

test/ashy_walnut_desk/interaction/outbound_idempotency_key_test.exs                 — outbound key determinism tests

test/ashy_walnut_desk/interaction/replay_audit_outcome_test.exs                     — replay outcome auditability tests

test/ashy_walnut_desk/interaction/inbound_delivery_retention_test.exs               — retention/TTL tests
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/action.ex                                           — outbound idempotency key attribute/action integration
lib/ashy_walnut_desk/interaction/interaction.ex                                      — register inbound delivery resource
specs/phase-3/architecture.md                                                        — align idempotency/dedupe contracts
```

## Implementation notes

Do not implement full outbound retry execution in this story. This story only delivers the replay/idempotency substrate required by story 3.5.

## Safety review

- Sensitive records touched? yes — inbound provider delivery identifiers + message linkage
- AI output to end user possible? no
- Guardrails applied? deterministic dedupe + audit outcomes
- Audit trail covered? yes — replay outcome events/records are test-verified

## Out of scope (will NOT do in this story)

- Twilio outbound retry worker behavior: deferred to story 3.5
- Compensation trigger flow: deferred to story 3.6
- Admin audit viewer UI: deferred to story 3.7

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/interaction/inbound_delivery_dedupe_test.exs
mix test test/ashy_walnut_desk/interaction/outbound_idempotency_key_test.exs
mix test test/ashy_walnut_desk/interaction/replay_audit_outcome_test.exs
mix test test/ashy_walnut_desk/interaction/inbound_delivery_retention_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
