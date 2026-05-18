# Story 3.6: Compensation Invocation Operator Flow + Countdown Parity

**Phase**: 3
**Estimate**: 2h
**Depends on**: 3.5
**Status**: planned

---

## Goal

Ship operator-triggered compensation sends through the same real adapter path with the same countdown and audit guarantees as primary outbound sends.

## Context

Phase 2 registered compensation but deferred invocation. Phase 3 requirements and architecture now require real compensation invocation via Twilio with explicit countdown parity.

## Reference specs

- `/AGENTS.md` §7.2 Human-in-the-loop, §7.3 Audit trail
- `/specs/architecture.md` §8 invariants, §10 failure modes
- `/specs/phase-3/architecture.md` §3.4 Compensation, §6.2 compensation flow
- `/specs/decisions/ADR-016` (chain discipline context)

## Acceptance criteria

- [ ] AC1: `Compensation` has an operator/admin trigger path that transitions from registered state through real send execution semantics. — Verify: `mix test test/ashy_walnut_desk/interaction/compensation_trigger_test.exs`
- [ ] AC2: Compensation invocation is blocked unless countdown requirements are satisfied (same 5-second rule; no carve-out). — Verify: `mix test test/ashy_walnut_desk/interaction/compensation_countdown_test.exs`
- [ ] AC3: Compensation trigger uses same Twilio adapter boundary and preserves idempotency/retry semantics expected by Phase 3. — Verify: `mix test test/ashy_walnut_desk/interaction/compensation_adapter_path_test.exs`
- [ ] AC4: Operator UI can trigger compensation from chain view and reflects resulting status outcome. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/compensation_invocation_test.exs`
- [ ] AC5: Compensation invocation writes auditable chain events and does not regress `mix audit.verify`. — Verify: `mix test test/ashy_walnut_desk/interaction/compensation_audit_chain_test.exs && mix audit.verify`

## Files to create

```
test/ashy_walnut_desk/interaction/compensation_trigger_test.exs                        — trigger action/state transition tests

test/ashy_walnut_desk/interaction/compensation_countdown_test.exs                      — countdown parity tests

test/ashy_walnut_desk/interaction/compensation_adapter_path_test.exs                   — adapter path/idempotency behavior tests

test/ashy_walnut_desk_web/live/inbox_live/compensation_invocation_test.exs             — operator UI invocation tests

test/ashy_walnut_desk/interaction/compensation_audit_chain_test.exs                    — audit chain verification tests
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/compensation.ex                                        — trigger action + policy + status handling
lib/ashy_walnut_desk_web/live/inbox_live/show.ex                                        — compensation invoke affordance/event
lib/ashy_walnut_desk/interaction/changes/chain_link.ex                                  — compensation execution event coverage
specs/phase-3/architecture.md                                                           — align compensation send sequence details
```

## Implementation notes

Compensation flow must remain explicit and auditable. Do not add autonomous compensation logic; invocation remains manual by operator.

## Safety review

- Sensitive records touched? yes — compensation body and outbound send metadata
- AI output to end user possible? no
- Guardrails applied? explicit operator trigger + countdown parity
- Audit trail covered? yes — compensation execution events + chain verification

## Out of scope (will NOT do in this story)

- Admin audit viewer implementation: deferred to story 3.7
- Webhook throttle/preflight integration bundle: deferred to story 3.8
- New provider implementations beyond Twilio: deferred to later phases

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/interaction/compensation_trigger_test.exs
mix test test/ashy_walnut_desk/interaction/compensation_countdown_test.exs
mix test test/ashy_walnut_desk/interaction/compensation_adapter_path_test.exs
mix test test/ashy_walnut_desk_web/live/inbox_live/compensation_invocation_test.exs
mix test test/ashy_walnut_desk/interaction/compensation_audit_chain_test.exs
mix audit.verify
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
