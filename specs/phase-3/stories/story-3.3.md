# Story 3.3: Inbound Twilio Webhook + Authenticity + Intake Defaults

**Phase**: 3
**Estimate**: 3h
**Depends on**: 3.2
**Status**: planned

---

## Goal

Implement Twilio inbound webhook intake with signature verification and the required defaults for Inbox creation, Identity resolution, and Conversation threading.

## Context

Inbound is a new public entry point. Phase 3 requires deterministic, auditable intake behavior that preserves Phase 2 chain integrity and does not rely on operator actors.

## Reference specs

- `/AGENTS.md` §7 Safety Rules
- `/specs/architecture.md` §8 Data invariants, §11 Security posture
- `/specs/phase-3/architecture.md` §1 Overview, §3.1 InboundDelivery, §3.3 Inbox, §5.1 Inbound sequence
- `/specs/decisions/ADR-024-inbound-intake-policy.md`

## Acceptance criteria

- [ ] AC1: `POST /webhook/twilio` validates Twilio signature and rejects invalid signatures with non-success response; invalid attempts are auditable. — Verify: `mix test test/ashy_walnut_desk_web/controllers/webhook/twilio_signature_test.exs`
- [ ] AC2: Valid webhook intake creates/links `Inbox`, `Conversation`, and inbound `Message` via named Ash actions only, using the internal inbound Inbox path (not operator `record_inbox`). — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_intake_test.exs`
- [ ] AC3: Identity default behavior is enforced: existing identifier links existing Identity; unknown identifier creates deterministic provisional Identity; malformed/ambiguous signal lands in deterministic auditable intake-failure path. — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_identity_policy_test.exs`
- [ ] AC4: Threading default is enforced: newest non-archived `(identity_id, channel_id)` Conversation is reused, otherwise new Conversation is created. — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_threading_test.exs`
- [ ] AC5: System-actor/inbound-only policy boundaries are enforced (inbound path can create inbox; same actor/path cannot execute send actions). — Verify: `mix test test/ashy_walnut_desk/interaction/inbound_actor_policy_test.exs`

## Files to create

```
lib/ashy_walnut_desk_web/controllers/webhook/twilio_controller.ex                 — Twilio webhook endpoint controller
lib/ashy_walnut_desk_web/controllers/webhook/twilio_signature_plug.ex             — request signature verification plug
lib/ashy_walnut_desk/interaction/inbound_intake.ex                                 — intake orchestration + defaults

test/ashy_walnut_desk_web/controllers/webhook/twilio_signature_test.exs            — signature verification tests

test/ashy_walnut_desk/interaction/inbound_intake_test.exs                          — inbound chain creation tests

test/ashy_walnut_desk/interaction/inbound_identity_policy_test.exs                 — identity default policy tests

test/ashy_walnut_desk/interaction/inbound_threading_test.exs                       — threading default tests

test/ashy_walnut_desk/interaction/inbound_actor_policy_test.exs                    — system actor policy boundary tests
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                                                 — add Twilio webhook route/pipeline wiring
lib/ashy_walnut_desk/interaction/inbox.ex                                          — internal-only inbound inbox action
lib/ashy_walnut_desk/identity/identity.ex                                          — provisional/unknown-identifier intake support
specs/phase-3/architecture.md                                                      — keep sequence and defaults aligned
```

## Implementation notes

This story establishes intake semantics only. Keep replay/idempotency persistence out (handled in 3.4) and outbound execution out (3.5).

## Safety review

- Sensitive records touched? yes — inbound identifiers + message bodies
- AI output to end user possible? no
- Guardrails applied? signature verification + internal-only intake action path
- Audit trail covered? yes — inbound intake event path is auditable per architecture

## Out of scope (will NOT do in this story)

- Inbound/outbound replay dedupe persistence contract: deferred to story 3.4
- Oban outbound retries and Twilio send semantics: deferred to story 3.5
- Compensation send invocation UX: deferred to story 3.6

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk_web/controllers/webhook/twilio_signature_test.exs
mix test test/ashy_walnut_desk/interaction/inbound_intake_test.exs
mix test test/ashy_walnut_desk/interaction/inbound_identity_policy_test.exs
mix test test/ashy_walnut_desk/interaction/inbound_threading_test.exs
mix test test/ashy_walnut_desk/interaction/inbound_actor_policy_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
