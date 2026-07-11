# Story 5.4: Retriever ladder (vector → lexical → none) + telemetry

**Phase**: 5
**Estimate**: 3h
**Depends on**: 5.3
**Status**: ready

---

## Goal

Ship `Knowledge.Retriever` — the never-raising retrieval ladder that
returns scored Manual excerpts (vector rung), degrades to pg_trgm
lexical matching, or reports `:none`, always scope-filtered to active
current-revision content.

## Context

The read side of the pipeline; consumed by generation integration
(5.5). Encodes the phase AC "a retrieval outage alone never hard-fails
generation".

## Reference specs

- `/specs/phase-5/requirements.md` §2 (degradation AC, scope AC)
- `/specs/phase-5/architecture.md` §4.1 (ladder), §5 (`:retrieval` config)

## Acceptance criteria

- [ ] AC1: `Retriever.retrieve/2` returns `{:ok, %RetrievalResult{mode, excerpts}}` for every input — including embedder errors, missing adapter, empty index, and disabled config — never raising and never returning `{:error, _}`. — Verify: `mix test test/ashy_walnut_desk/knowledge/retriever_test.exs`
- [ ] AC2: Vector rung ranks by cosine similarity with `top_k`/`min_score`/`token_budget` from `:retrieval` config; deterministic under the Fixture embedder. — Verify: `mix test test/ashy_walnut_desk/knowledge/retriever_vector_test.exs`
- [ ] AC3: Lexical rung serves staged-unembedded chunks via pg_trgm similarity when the embedder fails or is absent; `mode: :lexical` recorded. — Verify: `mix test test/ashy_walnut_desk/knowledge/retriever_fallback_test.exs`
- [ ] AC4: Property test: no excerpt ever comes from an archived, soft-deleted, or stale-revision Manual/chunk, under randomized fixture populations. — Verify: `mix test test/ashy_walnut_desk/knowledge/properties/retrieval_scope_test.exs`
- [ ] AC5: `[:awd, :knowledge, :retrieval, :stop]` telemetry fires with duration/chunk_count measurements and mode metadata. — Verify: `mix test test/ashy_walnut_desk/knowledge/retriever_telemetry_test.exs`

## Files to create

```
lib/ashy_walnut_desk/knowledge/retriever.ex
lib/ashy_walnut_desk/knowledge/retrieval_result.ex
test/ashy_walnut_desk/knowledge/retriever_test.exs
test/ashy_walnut_desk/knowledge/retriever_vector_test.exs
test/ashy_walnut_desk/knowledge/retriever_fallback_test.exs
test/ashy_walnut_desk/knowledge/properties/retrieval_scope_test.exs
test/ashy_walnut_desk/knowledge/retriever_telemetry_test.exs
```

## Files to modify

```
config/config.exs   — :retrieval defaults (top_k 4, min_score 0.5, token_budget 1_200, enabled?)
```

## Implementation notes

pgvector cosine query goes through a dedicated read on ManualChunk or
a fragment-based Ash calculation — keep raw SQL out of caller code;
if Ash expression support falls short, isolate the fragment inside the
resource's read preparation (still "domain logic through Ash
actions"). Query text bounded to 2K chars by the caller contract.

## Safety review

- Sensitive records touched? yes — chunk content read into memory for excerpting
- AI output to end user possible? no (context in, not output out)
- Guardrails applied? scope filters (property-tested), config kill-switch (`enabled?: false`)
- Audit trail covered? provenance persisted in 5.5

## Out of scope (will NOT do in this story)

- Prompt/worker integration + `ai_retrieval` persistence (5.5)
- Operator-facing badge (5.6)

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/knowledge/
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
