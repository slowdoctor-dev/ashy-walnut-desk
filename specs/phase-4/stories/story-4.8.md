# Story 4.8: Phase 4 Preflight + Deployer Docs + Integration/Regression Gate

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7
**Status**: done

---

## Goal

Close Phase 4 with operational hardening: executable AI preflight gate, deployer runbook updates, and end-to-end integration/regression verification across all phase ACs.

## Context

This is the final phase gate story mirroring Phase 3. Earlier stories deliver components; this story proves composition, operability, and non-regression.

## Reference specs

- `/AGENTS.md` §5 verification gates, §7 safety rules
- `/specs/architecture.md` §10 failure modes, §11 security posture
- `/specs/phase-4/architecture.md` §2 tooling (`mix phase4.ai.preflight`), §14 rollback, §16 PM hints
- `/specs/decisions/ADR-025-ai-adapter-via-req.md`

## Acceptance criteria

- [x] AC1: `mix phase4.ai.preflight` exists and fails fast on missing/invalid AI runtime configuration; supports an offline `--skip-network` mode. — Verify: `mix test test/mix/tasks/phase4_ai_preflight_test.exs`
- [x] AC2: Deployer docs cover AI env/config bootstrapping, persona setup, model allowlist, and preflight execution sequence. — Verify: `rg -n "phase4\.ai\.preflight|ANTHROPIC_API_KEY|model allowlist|persona" README.md specs/phase-4/architecture.md`
- [x] AC3: End-to-end integration test covers generate -> validate -> approve -> countdown -> send path with no autonomous send bypass. — Verify: `mix test test/integration/phase4_ai_draft_chain_e2e_test.exs`
- [x] AC4: Regression gate proves prior safety invariants remain green (`mix audit.verify`, honest-framing runtime tests, and interaction hardening suite). — Verify: `mix audit.verify && mix test test/ashy_walnut_desk/safety/validators/honest_framing_test.exs && mix test test/ashy_walnut_desk/interaction/hardening_test.exs`
- [x] AC5: Phase-level command set for AC closure is documented and executable from a clean environment. — Verify: `just verify && mix phase4.ai.preflight --skip-network`

## Files to create

```
lib/mix/tasks/phase4.ai.preflight.ex                                      — Phase 4 config/health preflight
test/mix/tasks/phase4_ai_preflight_test.exs                               — task behavior tests
test/integration/phase4_ai_draft_chain_e2e_test.exs                       — full phase integration test
```

## Files to modify

```
README.md                                                                  — deployer runbook updates
specs/phase-4/architecture.md                                              — integration verification command set, if needed
specs/phase-4/requirements.md                                              — status refresh (if changed during execution)
```

## Implementation notes

Keep this story integration-focused; do not introduce new product behavior unless needed to close explicit AC regressions.

## Safety review

- Sensitive records touched? yes — full AI generation and send-approval chain exercised
- AI output to end user possible? yes — generated drafts in review/send path
- Guardrails applied? validator chain + approval/countdown + policy gates
- Audit trail covered? yes — integration asserts chain/audit continuity

## Out of scope (will NOT do in this story)

- New model/provider feature work beyond Phase 4 requirements
- New domain-axis expansion (RAG/manual retrieval work remains Phase 5)

## Verification

```bash
just verify
# Plus story-specific:
mix test test/mix/tasks/phase4_ai_preflight_test.exs
mix phase4.ai.preflight --skip-network
mix test test/integration/phase4_ai_draft_chain_e2e_test.exs
mix audit.verify
mix test test/ashy_walnut_desk/safety/validators/honest_framing_test.exs
mix test test/ashy_walnut_desk/interaction/hardening_test.exs
```

## Notes during implementation

- Decisions made:
  - Preflight checks four config surfaces (key presence, `:default_model`
    in the model allowlist, `:ai_adapter` in the adapter allowlist, and
    active Persona `model_override` drift) before attempting the network
    health check; the health check is skipped (with an explanatory note)
    when config checks already failed, so the operator fixes config
    before burning a provider call.
  - Persona-override drift check added beyond the architecture §2 list:
    row-level allowlist validation only runs at create/update, so an
    allowlist shrink strands rows that would fail at generation time —
    exactly the "invalid AI runtime configuration" AC1 targets.
  - The e2e gate drives two generated candidates through the worker so
    approval exercises Q5 sibling supersession, and asserts the
    countdown refusal (`countdown_violation`) plus the `ValidatorPassed`
    approval block as the "no autonomous send bypass" proof.
- Spec drift noticed: `BASELINE.md` §6/§7/§13 still described Phase 2 as
  the frontier (pre-Phase-3 text; ADR list stopped at 021) — refreshed
  to the Phase 4 close as part of this story's doc pass.
- Gotchas to add to AGENTS.md §10: none added — AGENTS.md sits at its
  300-line cap, so recording here instead: sandboxed agent environments
  may block `repo.hex.pm` egress, making local `mix deps.get`
  impossible — develop against CI (`workflow_dispatch` on ci.yml) in
  that case.
