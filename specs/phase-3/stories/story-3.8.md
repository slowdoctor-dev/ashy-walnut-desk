# Story 3.8: Webhook Throttle + Deployer Docs + Phase Integration/Regression Gate

**Phase**: 3
**Estimate**: 3h
**Depends on**: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7
**Status**: planned

---

## Goal

Close Phase 3 with production-hardening glue: webhook abuse controls, deployer-facing setup/docs, and an integration gate proving all phase ACs and Phase 2 invariants remain intact.

## Context

This is the final integration story. Earlier stories deliver features; this story validates they compose correctly and are operable by deployers.

## Reference specs

- `/AGENTS.md` §5 verification gates, §7 safety rules
- `/specs/architecture.md` §10 failure modes, §11 security posture
- `/specs/phase-3/architecture.md` §1 flow overview, §8 operations/testing notes
- `/specs/decisions/ADR-023-oban-for-outbound-retry.md`

## Acceptance criteria

- [ ] AC1: Webhook endpoint pipeline enforces configured throttle and returns deterministic non-success responses (e.g., 429) under abuse conditions. — Verify: `mix test test/ashy_walnut_desk_web/controllers/webhook/webhook_throttle_test.exs`
- [ ] AC2: Deployer bootstrap docs cover Twilio env config, channel registration, and preflight sequence with executable commands. — Verify: `rg -n "TWILIO_ACCOUNT_SID|phase3.webhook.preflight|twilio-sms" README.md specs/phase-3/architecture.md`
- [ ] AC3: Preflight gate (`mix phase3.webhook.preflight`) is included in phase integration verification path. — Verify: `mix phase3.webhook.preflight`
- [ ] AC4: End-to-end integration test covers inbound webhook -> chain visibility -> outbound Twilio execute -> compensation invoke -> audit viewer continuity path (with provider mocked/stubbed at test boundary). — Verify: `mix test test/integration/phase3_twilio_chain_e2e_test.exs`
- [ ] AC5: Phase-level regression gate proves no drift against prior safety invariants (`mix audit.verify`, honest-framing test, and core interaction hardening tests remain green). — Verify: `mix audit.verify && mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs && mix test test/ashy_walnut_desk/interaction/hardening_test.exs`

## Files to create

```
test/ashy_walnut_desk_web/controllers/webhook/webhook_throttle_test.exs               — webhook abuse/throttle behavior tests

test/integration/phase3_twilio_chain_e2e_test.exs                                      — full phase e2e integration test
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                                                     — webhook throttled pipeline wiring/finalization
README.md                                                                              — deployer setup/runbook updates for Twilio + preflight
specs/phase-3/architecture.md                                                          — operational verification commands + deployment notes
specs/phase-3/requirements.md                                                          — set phase story statuses as work progresses (if needed)
```

## Implementation notes

Keep this story integration-focused. Avoid new domain behavior unless needed to close explicit AC gaps discovered by integration tests.

## Safety review

- Sensitive records touched? yes — inbound/outbound integration paths exercised
- AI output to end user possible? no
- Guardrails applied? webhook throttle + signature verification + countdown + audit checks
- Audit trail covered? yes — integration test includes chain continuity verification

## Out of scope (will NOT do in this story)

- New adapter/provider beyond Twilio
- New domain features outside Phase 3 requirements
- Additional admin tooling beyond `AuditLive.Chain`

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk_web/controllers/webhook/webhook_throttle_test.exs
mix phase3.webhook.preflight
mix test test/integration/phase3_twilio_chain_e2e_test.exs
mix audit.verify
mix test test/ashy_walnut_desk_web/safety/honest_framing_test.exs
mix test test/ashy_walnut_desk/interaction/hardening_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
