# Story 4.4: Safety Validator Stack (Baseline + Honest-Framing Runtime + Composite)

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.2
**Status**: planned

---

## Goal

Ship the validator subsystem that deterministically evaluates AI output before approval readiness, including runtime honest-framing checks.

## Context

Phase 2 source-level honest-framing checks do not cover runtime AI text. Phase 4 requires validator composition that can block unsafe generated output and persist structured outcomes.

## Reference specs

- `/AGENTS.md` §6 user-facing gettext rule, §7.1 no unvalidated domain assertions
- `/specs/architecture.md` §10 failure modes, §11 security posture
- `/specs/phase-4/architecture.md` §1 Safety subsystem, §2 Affected modules (`Safety.*`), §6 validator result contract

## Acceptance criteria

- [ ] AC1: `Safety.Validator` behaviour and `Validators.Composite` chain exist with deterministic merged result schema. — Verify: `mix test test/ashy_walnut_desk/safety/validator_composite_test.exs`
- [ ] AC2: `Validators.Baseline` blocks prohibited claims and guarantee-style phrasing per framework rules. — Verify: `mix test test/ashy_walnut_desk/safety/validators/baseline_test.exs`
- [ ] AC3: `Validators.HonestFraming` evaluates runtime generated body text (not source files) and returns violation codes/messages. — Verify: `mix test test/ashy_walnut_desk/safety/validators/honest_framing_test.exs`
- [ ] AC4: Validator-facing operator messages are gettext-backed (no hardcoded UI error strings in validator output path). — Verify: `rg -n "gettext\(" lib/ashy_walnut_desk/safety && mix test test/ashy_walnut_desk/safety/validator_i18n_test.exs`

## Files to create

```
lib/ashy_walnut_desk/safety/validator.ex                         — behaviour
lib/ashy_walnut_desk/safety/validator_result.ex                  — result struct
lib/ashy_walnut_desk/safety/deployment_validator.ex              — deployer extension contract
lib/ashy_walnut_desk/safety/validators/composite.ex              — validator chain
lib/ashy_walnut_desk/safety/validators/baseline.ex               — framework checks
lib/ashy_walnut_desk/safety/validators/honest_framing.ex         — runtime framing check

test/ashy_walnut_desk/safety/validator_composite_test.exs
test/ashy_walnut_desk/safety/validators/baseline_test.exs
test/ashy_walnut_desk/safety/validators/honest_framing_test.exs
test/ashy_walnut_desk/safety/validator_i18n_test.exs
```

## Files to modify

```
config/config.exs                                                 — validator chain wiring / extension points
priv/gettext/default.pot                                          — extracted messages
priv/gettext/*.po                                                 — localized validator keys
```

## Implementation notes

Do not decide override policy in this story beyond surfacing deterministic result signals; final override semantics are enforced at Draft action layer.

## Safety review

- Sensitive records touched? yes — generated message bodies
- AI output to end user possible? yes (eventually; this story defines the gate)
- Guardrails applied? baseline + runtime honest-framing + composite
- Audit trail covered? via downstream Draft action persistence (story 4.5)

## Out of scope (will NOT do in this story)

- Draft action/state transitions: deferred to story 4.5
- Oban orchestration and telemetry wiring: deferred to story 4.6

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/safety/validator_composite_test.exs
mix test test/ashy_walnut_desk/safety/validators/baseline_test.exs
mix test test/ashy_walnut_desk/safety/validators/honest_framing_test.exs
mix test test/ashy_walnut_desk/safety/validator_i18n_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
