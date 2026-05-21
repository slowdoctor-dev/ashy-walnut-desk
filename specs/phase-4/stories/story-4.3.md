# Story 4.3: Anthropic Req Adapter + Config/Allowlist + Conformance Tests

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.2
**Status**: planned

---

## Goal

Implement the real Req-direct Anthropic adapter behind the `AI.Adapter` contract with explicit model allowlist and deterministic conformance tests.

## Context

ADR-025 resolves provider posture to Req-direct instead of `ash_ai`. This story delivers the real adapter boundary while preserving the fixture seam from story 4.2.

## Reference specs

- `/AGENTS.md` §4 stack constraints, §7 safety rules
- `/specs/phase-4/architecture.md` §1 Overview, §2 Affected modules (`AI.Adapters.Anthropic`), §11 decisions
- `/specs/decisions/ADR-025-ai-adapter-via-req.md`

## Acceptance criteria

- [ ] AC1: `AI.Adapters.Anthropic` implements `AI.Adapter.complete/2` using Req with required auth/config path and normalized response shape. — Verify: `mix test test/ashy_walnut_desk/ai/adapters/anthropic_test.exs`
- [ ] AC2: Model allowlist/default-model config enforcement is implemented; disallowed model requests fail deterministically. — Verify: `mix test test/ashy_walnut_desk/ai/model_allowlist_test.exs`
- [ ] AC3: Contract conformance suite runs against fixture and Anthropic adapters (network mocked), asserting identical shape-level behavior. — Verify: `mix test test/ashy_walnut_desk/ai/adapter_conformance_test.exs`
- [ ] AC4: Runtime config wiring reads Anthropic key from env with production fail-fast semantics. — Verify: `mix test test/ashy_walnut_desk/ai/runtime_config_test.exs`

## Files to create

```
lib/ashy_walnut_desk/ai/adapters/anthropic.ex                  — Req-direct Anthropic adapter

test/ashy_walnut_desk/ai/adapters/anthropic_test.exs           — adapter behavior tests
test/ashy_walnut_desk/ai/model_allowlist_test.exs              — allowlist enforcement
test/ashy_walnut_desk/ai/adapter_conformance_test.exs          — fixture vs anthropic shape conformance
test/ashy_walnut_desk/ai/runtime_config_test.exs               — env config semantics
```

## Files to modify

```
config/runtime.exs                                              — ANTHROPIC_API_KEY + default model enforcement
config/config.exs                                               — ai adapter allowlist/default model settings
```

## Implementation notes

Keep this story at adapter/config boundary only; do not wire Draft actions or LiveView yet.

## Safety review

- Sensitive records touched? yes — model IO boundary
- AI output to end user possible? no (not connected to send/review path yet)
- Guardrails applied? adapter contract normalization + model allowlist
- Audit trail covered? N/A in this story

## Out of scope (will NOT do in this story)

- Validator chain: deferred to story 4.4
- Draft generation state machine: deferred to story 4.5
- Worker orchestration: deferred to story 4.6

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/ai/adapters/anthropic_test.exs
mix test test/ashy_walnut_desk/ai/model_allowlist_test.exs
mix test test/ashy_walnut_desk/ai/adapter_conformance_test.exs
mix test test/ashy_walnut_desk/ai/runtime_config_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
