# Story 5.2: Embedder behaviour + Fixture + Voyage adapter + conformance

**Phase**: 5
**Estimate**: 3h
**Depends on**: —
**Status**: ready

---

## Goal

Ship the pluggable embedding boundary (ADR-026): `Knowledge.Embedder`
behaviour, deterministic `Embedders.Fixture`, Req-direct
`Embedders.Voyage`, config allowlists, and a conformance suite both
implementations pass.

## Context

Third instance of the adapter pattern (ADR-022/ADR-025). Independent
of 5.1 — pure embedding surface; 5.3 wires it to chunks.

## Reference specs

- `/specs/phase-5/architecture.md` §2 (embedding boundary), §5 config, §9 external integrations
- `/specs/decisions/ADR-026-embeddings-via-embedder-behaviour.md`
- `/specs/decisions/ADR-025-ai-adapter-via-req.md` (error taxonomy exemplar)

## Acceptance criteria

- [ ] AC1: `Knowledge.Embedder` behaviour defines `embed(texts, opts) :: {:ok, [[float()]]} | {:error, :transient | :permanent | :rate_limited | :timeout | term()}`; both impls implement it. — Verify: `mix test test/ashy_walnut_desk/knowledge/embedder_conformance_test.exs`
- [ ] AC2: Fixture embedder is deterministic, offline, L2-normalized at the configured dimension (1024), and gives higher cosine similarity to overlapping texts than to disjoint ones. — Verify: `mix test test/ashy_walnut_desk/knowledge/embedders/fixture_test.exs`
- [ ] AC3: Voyage adapter builds the documented request envelope (bearer key, model, `input_type`), classifies 429/5xx/400/401-403/timeout per the shared taxonomy, batches ≤ 128 inputs, and is stubbed via `:voyage_req_options` (no network in tests). — Verify: `mix test test/ashy_walnut_desk/knowledge/embedders/voyage_test.exs`
- [ ] AC4: Config ships `:embedding_adapter` (Fixture default), `:embedding_adapter_allowlist`, `:embedding_model(_allowlist)`, `:embedding_dimension`; resolution rejects non-allowlisted modules. — Verify: `mix test test/ashy_walnut_desk/knowledge/embedder_config_test.exs`

## Files to create

```
lib/ashy_walnut_desk/knowledge/embedder.ex                       — behaviour + resolve/0
lib/ashy_walnut_desk/knowledge/embedders/fixture.ex              — hashed bag-of-words
lib/ashy_walnut_desk/knowledge/embedders/voyage.ex               — Req-direct impl
test/ashy_walnut_desk/knowledge/embedder_conformance_test.exs
test/ashy_walnut_desk/knowledge/embedders/fixture_test.exs
test/ashy_walnut_desk/knowledge/embedders/voyage_test.exs
test/ashy_walnut_desk/knowledge/embedder_config_test.exs
```

## Files to modify

```
config/config.exs    — §5 embedding keys (Fixture default)
config/runtime.exs   — EMBEDDING_ADAPTER=voyage|none prod gate (+ VOYAGE_API_KEY)
```

## Implementation notes

Mirror `AI.Adapters.Anthropic` structure (headers, error mapping,
`test_overrides` via app env). `EMBEDDING_ADAPTER=none` maps to
Fixture-module-absent posture: set `:retrieval` `vector?`-capability
off by leaving `:embedding_adapter` unset in prod — Retriever (5.4)
treats missing adapter as "skip vector rung". Key never logged.

## Safety review

- Sensitive records touched? indirectly — future chunk content flows through `embed/2`
- AI output to end user possible? no
- Guardrails applied? allowlist + explicit prod env gate (no silent egress)
- Audit trail covered? N/A (stateless boundary; provenance lands in 5.5)

## Out of scope (will NOT do in this story)

- Chunk staging/stamping (5.3), retrieval ladder (5.4), preflight (5.7)

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
