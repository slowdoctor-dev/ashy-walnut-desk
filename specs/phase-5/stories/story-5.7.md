# Story 5.7: Phase 5 preflight + deployer docs + integration/regression gate

**Phase**: 5
**Estimate**: 3h
**Depends on**: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6
**Status**: ready

---

## Goal

Close Phase 5: executable knowledge preflight gate, deployer runbook
(embedding posture + data-egress implications), and end-to-end
integration/regression verification across all phase ACs.

## Context

Phase gate story mirroring 3.8/4.8. Earlier stories deliver
components; this proves composition, operability, and non-regression.

## Reference specs

- `/specs/phase-5/requirements.md` §2 (all phase ACs)
- `/specs/phase-5/architecture.md` §2a (preflight), §5 (prod config), §14 (testing)
- `/specs/decisions/ADR-026-embeddings-via-embedder-behaviour.md` (follow-ups)

## Acceptance criteria

- [ ] AC1: `mix phase5.knowledge.preflight` fails fast on non-allowlisted embedder, dimension mismatch (config vs column vs model), and missing provider key when the configured embedder needs one; `--skip-network` supported; healthy config passes with one low-cost embed call in network mode. — Verify: `mix test test/mix/tasks/phase5_knowledge_preflight_test.exs`
- [ ] AC2: Deployer docs (README runbook) cover `EMBEDDING_ADAPTER=voyage|none`, `VOYAGE_API_KEY`, data-egress implications, Manual authoring flow, and the preflight sequence. — Verify: `rg -n "phase5\.knowledge\.preflight|EMBEDDING_ADAPTER|VOYAGE_API_KEY" README.md specs/phase-5/architecture.md`
- [ ] AC3: End-to-end integration test covers author → index → retrieve → generate (grounded) → validate → approve → countdown → send, asserting `ai_retrieval` provenance, badge rendering, and an all-`:ok` audit chain including the extended payload. — Verify: `mix test test/integration/phase5_knowledge_rag_e2e_test.exs`
- [ ] AC4: Regression gate proves Phase 2–4 invariants with retrieval disabled and enabled: `mix audit.verify`, Phase 4 e2e, hardening suite. — Verify: `mix audit.verify && mix test test/integration/phase4_ai_draft_chain_e2e_test.exs test/ashy_walnut_desk/interaction/hardening_test.exs`
- [ ] AC5: Phase-close command set documented and executable from a clean environment. — Verify: `just verify && mix phase5.knowledge.preflight --skip-network`

## Files to create

```
lib/mix/tasks/phase5.knowledge.preflight.ex
test/mix/tasks/phase5_knowledge_preflight_test.exs
test/integration/phase5_knowledge_rag_e2e_test.exs
```

## Files to modify

```
README.md                          — Phase 5 deployer runbook
BASELINE.md                        — phase status + ADR count refresh
specs/phase-5/requirements.md      — status refresh (if drifted)
```

## Implementation notes

Preflight mirrors `phase4.ai.preflight` (config sweep → optional
network probe, `Mix.raise` on failure). The e2e extends the Phase 4
e2e shape with a Manual + drained `:knowledge_indexing` queue up
front. Keep it integration-focused; no new product behavior.

## Safety review

- Sensitive records touched? yes — full knowledge + generation + send chain exercised
- AI output to end user possible? yes — grounded drafts through the approval path
- Guardrails applied? validator + approval/countdown + retrieval scope filters
- Audit trail covered? e2e asserts chain continuity incl. new payload fields

## Out of scope (will NOT do in this story)

- Retrieval-quality tuning beyond deterministic assertions
- Phase 6+ concerns (multi-tenant decision happens at phase retro, not in-code)

## Verification

```bash
just verify
mix test test/mix/tasks/phase5_knowledge_preflight_test.exs
mix phase5.knowledge.preflight --skip-network
mix test test/integration/phase5_knowledge_rag_e2e_test.exs
mix audit.verify
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
