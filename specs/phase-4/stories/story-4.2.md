# Story 4.2: AI Subsystem Skeleton (Adapter Contract + Fixture + Prompt Assembly)

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.1
**Status**: planned

---

## Goal

Create the provider-agnostic AI core primitives (`AI.Adapter`, fixture adapter, prompt/response structs, and prompt assembler) without invoking Anthropic yet.

## Context

Phase 4 needs deterministic test seams before real provider integration. This story defines the contract and deterministic fixture path used by downstream worker and validator stories.

## Reference specs

- `/AGENTS.md` §4 Stack, §7 Safety Rules
- `/specs/architecture.md` §3 LLM as glue, §9 External integrations
- `/specs/phase-4/architecture.md` §1 Overview, §2 Affected modules (AI domain), §4 Prompt assembly rules

## Acceptance criteria

- [ ] AC1: `AI.Adapter` behaviour and `AI.Adapters.Fixture` test implementation exist with stable `complete/2` contract. — Verify: `mix test test/ashy_walnut_desk/ai/adapter_contract_test.exs`
- [ ] AC2: `%AI.Prompt{}` and `%AI.Response{}` structs exist with fields required by architecture (text, usage, stop reason, etc.). — Verify: `mix test test/ashy_walnut_desk/ai/prompt_response_test.exs`
- [ ] AC3: `AI.PromptAssembler` builds allowlisted prompt context only and emits stable cache marker metadata. — Verify: `mix test test/ashy_walnut_desk/ai/prompt_assembler_test.exs`
- [ ] AC4: No direct LiveView path can call provider APIs; this story ships only the internal adapter seam + tests. — Verify: `rg -n "Req\.post|Anthropic|AI\.Adapters\.Anthropic" lib/ashy_walnut_desk_web`

## Files to create

```
lib/ashy_walnut_desk/ai/ai.ex                                  — namespace/domain shell
lib/ashy_walnut_desk/ai/adapter.ex                             — behaviour contract
lib/ashy_walnut_desk/ai/adapters/fixture.ex                    — deterministic test adapter
lib/ashy_walnut_desk/ai/prompt.ex                              — prompt struct
lib/ashy_walnut_desk/ai/response.ex                            — response struct
lib/ashy_walnut_desk/ai/prompt_assembler.ex                    — context assembly

test/ashy_walnut_desk/ai/adapter_contract_test.exs             — contract tests
test/ashy_walnut_desk/ai/prompt_response_test.exs              — struct invariants
test/ashy_walnut_desk/ai/prompt_assembler_test.exs             — allowlist/cache marker tests
```

## Files to modify

```
config/config.exs                                               — AI adapter/module defaults for test/dev
```

## Implementation notes

Keep provider calls out of scope; fixture must be deterministic so worker/validator stories can test without network.

## Safety review

- Sensitive records touched? yes — prompt assembly includes customer context
- AI output to end user possible? not yet (internal primitives only)
- Guardrails applied? prompt context allowlist and cache marker stability checks
- Audit trail covered? N/A in this story

## Out of scope (will NOT do in this story)

- Anthropic real adapter and Req wiring: deferred to story 4.3
- Validator chain: deferred to story 4.4
- Draft action/state transitions: deferred to story 4.5

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/ai/adapter_contract_test.exs
mix test test/ashy_walnut_desk/ai/prompt_response_test.exs
mix test test/ashy_walnut_desk/ai/prompt_assembler_test.exs
rg -n "Req\.post|Anthropic|AI\.Adapters\.Anthropic" lib/ashy_walnut_desk_web
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
