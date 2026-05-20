# Story 4.8: Phase 4 Preflight + Deployer Docs + Integration/Regression Gate

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7
**Status**: planned

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

- [ ] AC1: `mix phase4.ai.preflight` exists and fails fast on missing/invalid AI runtime configuration; supports an offline `--skip-network` mode. — Verify: `mix test test/mix/tasks/phase4_ai_preflight_test.exs`
- [ ] AC2: Deployer docs cover AI env/config bootstrapping, persona setup, model allowlist, and preflight execution sequence. — Verify: `rg -n "phase4\.ai\.preflight|ANTHROPIC_API_KEY|model allowlist|persona" README.md specs/phase-4/architecture.md`
- [ ] AC3: End-to-end integration test covers generate -> validate -> approve -> countdown -> send path with no autonomous send bypass. — Verify: `mix test test/integration/phase4_ai_draft_chain_e2e_test.exs`
- [ ] AC4: Regression gate proves prior safety invariants remain green (`mix audit.verify`, honest-framing runtime tests, and interaction hardening suite). — Verify: `mix audit.verify && mix test test/ashy_walnut_desk/safety/validators/honest_framing_test.exs && mix test test/ashy_walnut_desk/interaction/hardening_test.exs`
- [ ] AC5: Phase-level command set for AC closure is documented and executable from a clean environment. — Verify: `just verify && mix phase4.ai.preflight --skip-network`

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

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
