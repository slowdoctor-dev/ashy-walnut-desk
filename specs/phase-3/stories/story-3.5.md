# Story 3.5: Outbound Twilio Execution + Oban Retry/Terminal Failure Semantics

**Phase**: 3
**Estimate**: 3h
**Depends on**: 3.4
**Status**: done

---

## Goal

Execute outbound sends through Twilio with durable Oban retry semantics and deterministic terminal failure handling, preserving approval/countdown invariants.

## Context

With adapter contract and idempotency substrate in place, this story shifts outbound execution from stub/inline assumptions to real Twilio network behavior with background job reliability.

## Reference specs

- `/AGENTS.md` §7.2 Human-in-the-loop, §7.3 Audit trail
- `/specs/architecture.md` §9 Channel adapters, §10 Failure modes
- `/specs/phase-3/architecture.md` §1 Overview, §3.5 Action, §6 outbound flow
- `/specs/decisions/ADR-023-oban-for-outbound-retry.md`

## Acceptance criteria

- [ ] AC1: `Action.execute` schedules outbound job execution and does not bypass server-side countdown enforcement. — Verify: `mix test test/ashy_walnut_desk/interaction/action_execute_enqueue_test.exs`
- [ ] AC2: Outbound worker executes Twilio send path with stable idempotency key across retries. — Verify: `mix test test/ashy_walnut_desk/interaction/jobs/outbound_send_test.exs`
- [ ] AC3: Transient provider/network failures retry per configured envelope; permanent or exhausted retries end in deterministic terminal failure state on `Action`. — Verify: `mix test test/ashy_walnut_desk/interaction/jobs/outbound_retry_policy_test.exs`
- [ ] AC4: Successful job completion updates chain state (`Action`, outbound `Message`, `Inbox`) and keeps audit-chain verification green. — Verify: `mix test test/ashy_walnut_desk/interaction/action_execute_chain_integration_test.exs && mix audit.verify`
- [ ] AC5: Disabled channels cannot send even when job executes. — Verify: `mix test test/ashy_walnut_desk/interaction/channel_disable_execute_guard_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/jobs/outbound_send.ex                                — Oban outbound worker
lib/ashy_walnut_desk/interaction/changes/enqueue_outbound_send.ex                     — enqueue change for Action.execute

test/ashy_walnut_desk/interaction/action_execute_enqueue_test.exs                      — enqueue/countdown behavior tests

test/ashy_walnut_desk/interaction/jobs/outbound_send_test.exs                          — worker success/idempotency behavior

test/ashy_walnut_desk/interaction/jobs/outbound_retry_policy_test.exs                  — transient/permanent failure policy tests

test/ashy_walnut_desk/interaction/action_execute_chain_integration_test.exs            — full chain completion integration test

test/ashy_walnut_desk/interaction/channel_disable_execute_guard_test.exs               — disabled-channel guard test
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/action.ex                                              — execute action scheduling + status semantics
lib/ashy_walnut_desk/interaction/changes/execute_outbound.ex                            — align with worker-driven execution path
config/runtime.exs                                                                       — outbound queue configuration
specs/phase-3/architecture.md                                                           — align retry envelope and status flow
```

## Implementation notes

Use existing Phase 2 chain invariants as non-negotiable constraints. The story may introduce intermediate scheduling status semantics as long as phase ACs remain testable and invariant-safe.

## Safety review

- Sensitive records touched? yes — outbound message body and provider response metadata
- AI output to end user possible? no
- Guardrails applied? approval + countdown + channel enable/disable guard
- Audit trail covered? yes — execution outcomes remain chain-verifiable

## Out of scope (will NOT do in this story)

- Compensation trigger operator flow: deferred to story 3.6
- AuditLive admin viewer: deferred to story 3.7
- Webhook throttle/preflight docs/integration gate: deferred to story 3.8

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/interaction/action_execute_enqueue_test.exs
mix test test/ashy_walnut_desk/interaction/jobs/outbound_send_test.exs
mix test test/ashy_walnut_desk/interaction/jobs/outbound_retry_policy_test.exs
mix test test/ashy_walnut_desk/interaction/action_execute_chain_integration_test.exs
mix test test/ashy_walnut_desk/interaction/channel_disable_execute_guard_test.exs
mix audit.verify
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
