# Story 5.3: Chunker + ManualChunk resource + indexing worker

**Phase**: 5
**Estimate**: 3h
**Depends on**: 5.1, 5.2
**Status**: done

---

## Goal

Turn Manual bodies into embedded, queryable `ManualChunk` rows via a
pure chunker and an Oban `:knowledge_indexing` worker with
content-hash reuse and stale-revision pruning.

## Context

Bridges authoring (5.1) and the embedding boundary (5.2); retrieval
(5.4) queries what this story persists.

## Reference specs

- `/specs/phase-5/architecture.md` §3.2 (ManualChunk), §4.2 (pipeline), §10 (vector column + indexes)
- `/AGENTS.md` §10 gotchas (AshOban/Oban queue config; hand-authored migrations)

## Acceptance criteria

- [x] AC1: `Chunker.chunk/1` splits on blank lines, greedy-merges to ≤ 1,600 chars, hard-wraps oversized paragraphs, emits `{position, content, content_hash}`; property test proves full non-whitespace coverage + determinism. — Verify: `mix test test/ashy_walnut_desk/knowledge/chunker_test.exs`
- [x] AC2: `ManualChunk` resource exists per architecture §3.2 with worker-gated `:stage`, `:stamp_embedding`, `:prune_revisions` (hard delete, documented ADR-019 exception) and admin-only read. — Verify: `mix test test/ashy_walnut_desk/knowledge/manual_chunk_test.exs`
- [x] AC3: `ChunkAndEmbedWorker` (queue `:knowledge_indexing`) stages chunks for the Manual's current revision, reuses vectors for unchanged `content_hash`, stamps embeddings via the configured Embedder, prunes superseded revisions, and noops on stale jobs. — Verify: `mix test test/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_worker_test.exs`
- [x] AC4: Manual `:author`/`:revise` enqueue the worker (`EnqueueIndexing`); embed `:permanent` failures leave staged-unembedded rows (lexical-servable) without failing the job; transient classes raise for Oban retry. — Verify: `mix test test/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_failure_test.exs`
- [x] AC5: Migrations add `manual_chunks` with `vector(1024)` column, unique `(manual_id, revision, position)`, HNSW + trgm indexes (hand-authored where the generator lacks support); `--check` stays green. — Verify: `mix ecto.migrate && mix ash_postgres.generate_migrations --check`

## Files to create

```
lib/ashy_walnut_desk/knowledge/chunker.ex
lib/ashy_walnut_desk/knowledge/manual_chunk.ex
lib/ashy_walnut_desk/knowledge/changes/enqueue_indexing.ex
lib/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_worker.ex
priv/repo/migrations/<ts>_add_manual_chunks.exs               — generated + hand-authored index follow-up
test/ashy_walnut_desk/knowledge/chunker_test.exs
test/ashy_walnut_desk/knowledge/manual_chunk_test.exs
test/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_worker_test.exs
test/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_failure_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/knowledge/knowledge.ex   — register ManualChunk
lib/ashy_walnut_desk/knowledge/manual.ex      — EnqueueIndexing change
config/config.exs + config/runtime.exs        — :knowledge_indexing queue
config/test.exs                               — queue under Oban manual testing
```

## Implementation notes

Worker gating mirrors `FromGenerationWorker`. If the installed
ash_postgres lacks a vector type, model `embedding` as a hand-authored
column with `Postgrex` custom type per architecture §10 note — do not
fight the generator. Drain `:knowledge_indexing` in tests like
`:ai_generation`.

## Safety review

- Sensitive records touched? yes — chunk `content` (`sensitive? true`); embed payloads carry Manual content only (no Identity PII by construction — asserted in tests)
- AI output to end user possible? no
- Guardrails applied? worker-only writes; scope filters
- Audit trail covered? Manual writes paper-trailed (5.1); chunks are derived data (documented exception)

## Out of scope (will NOT do in this story)

- Retrieval queries (5.4), prompt integration (5.5)

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/knowledge/
```

## Notes during implementation

- Decisions made: vector reuse keys on content_hash across ALL
  existing rows (any revision) so title-only revisions re-stage but
  never re-embed; prune runs after the embed decision so a transient
  raise leaves stale rows for the retry.
- Spec drift noticed: pgvector requires a custom Postgrex types module
  (AshPostgres.Extensions.Vector) — added lib/ashy_walnut_desk/
  postgrex_types.ex + repo `types:` config; architecture §10 said
  "hand-author where the generator lacks support" and this was the
  concrete instance (plus hand-authored HNSW/trgm index migration).
- Gotchas to add to AGENTS.md §10: `vector` columns fail with
  "type `vector` can not be handled" until Postgrex.Types.define with
  AshPostgres.Extensions.Vector is wired into the repo config.
