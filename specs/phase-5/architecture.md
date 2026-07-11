# Phase 5 — Architecture

> Architect-persona output for `specs/phase-5/requirements.md`.
> Companion decision record: `specs/decisions/ADR-026-embeddings-via-embedder-behaviour.md`.

## 1. Overview

Phase 5 adds the Knowledge-axis operational layer: deployment-authored
`Manual` content, a background chunk→embed pipeline, and a retrieval
step that grounds Phase 4 draft generation in that content — with
provenance persisted on the Draft and surfaced through the audit chain.

```
                       (admin authors/revises)
                                 │
                      Knowledge.Manual  ──paper-trail──▶ versions
                                 │ :author / :revise
                                 ▼  (enqueue)
              Oban :knowledge_indexing ── ChunkAndEmbedWorker
                                 │  Chunker (pure)  +  Embedder (adapter)
                                 ▼
                      Knowledge.ManualChunk (content + vector)
                                 ▲
                                 │ top-k similarity (pgvector)
                                 │ fallback: pg_trgm lexical
                                 │ fallback: :none (explicit)
   GenerationWorker ─▶ Knowledge.Retriever ─▶ retrieval block ─▶ PromptAssembler
        │                                                            │
        └── Draft.ai_retrieval (provenance) ◀────────────────────────┘
                                 │
                :draft_generation_completed payload extension
                     (retrieval_mode, retrieval_chunk_count)
```

Everything downstream of generation is untouched: validator gate,
approve, countdown, execute, audit chain (ADR-005/013/016 invariants).
Retrieval is read-only context assembly; it introduces no send path.

Trade-off headline: **retrieval lives in the worker, not in a new
service**. One extra provider call (query embedding) per generation in
the happy path, at the cost of worker latency — acceptable because
generation is already async behind Oban and the fallback ladder keeps
the worker from ever blocking on the embedding provider.

## 2. Affected modules

### New (Knowledge axis)

- `lib/ashy_walnut_desk/knowledge/manual.ex` — `Ash.Resource`; authored
  operational knowledge (§3.1).
- `lib/ashy_walnut_desk/knowledge/manual_chunk.ex` — `Ash.Resource`;
  derived chunk rows with embeddings (§3.2).
- `lib/ashy_walnut_desk/knowledge/chunker.ex` — pure paragraph/size
  chunker; content-hash per chunk.
- `lib/ashy_walnut_desk/knowledge/retriever.ex` — retrieval ladder
  (vector → lexical → none) returning a `RetrievalResult` struct.
- `lib/ashy_walnut_desk/knowledge/retrieval_result.ex` — struct:
  `mode`, `excerpts` (list of `%{manual_id, manual_slug, revision,
  position, content, content_hash, score, embedder}`).
- `lib/ashy_walnut_desk/knowledge/changes/enqueue_indexing.ex` —
  enqueues `ChunkAndEmbedWorker` after `:author`/`:revise`.
- `lib/ashy_walnut_desk/knowledge/jobs/chunk_and_embed_worker.ex` —
  Oban worker, queue `:knowledge_indexing` (§4.2).

### New (Embedding adapter boundary — ADR-026)

- `lib/ashy_walnut_desk/knowledge/embedder.ex` — behaviour:
  `embed(texts :: [String.t()], opts) :: {:ok, [[float()]]} | {:error,
  :transient | :permanent | :rate_limited | :timeout | term()}`.
- `lib/ashy_walnut_desk/knowledge/embedders/fixture.ex` — deterministic
  hashed bag-of-words vectors; test/dev default. No network.
- `lib/ashy_walnut_desk/knowledge/embedders/voyage.ex` — Req-direct
  Voyage AI reference implementation (§9). Prod default when configured.

### Modified

- `lib/ashy_walnut_desk/knowledge/knowledge.ex` — register Manual +
  ManualChunk in the domain.
- `lib/ashy_walnut_desk/ai/prompt_assembler.ex` — accepts an optional
  `retrieval` input; renders a non-cached "Deployment knowledge" system
  block after the cached framework/persona blocks (§4.3).
- `lib/ashy_walnut_desk/ai/jobs/generation_worker.ex` — calls
  `Retriever.retrieve/2` before prompt assembly; persists
  `ai_retrieval` at `:complete_generation`; telemetry (§4.1).
- `lib/ashy_walnut_desk/interaction/draft.ex` — new `ai_retrieval`
  attribute (sensitive, worker-writable only, admin/operator-readable
  per existing AI-field policy).
- `lib/ashy_walnut_desk/interaction/changes/chain_link.ex` +
  `audit_chain.ex` — `:draft_generation_completed` payload gains
  `retrieval_mode` + `retrieval_chunk_count` (payload-allowlist
  extension, no new event type — resolved question Q4, §12).
- `lib/ashy_walnut_desk_web/live/manual_live/*` — admin authoring
  surface (§6).
- `lib/ashy_walnut_desk_web/live/inbox_live/generation_panel.ex` —
  retrieval provenance badge (count + mode) on candidates.
- `config/config.exs` / `config/runtime.exs` / `config/test.exs` —
  §5 configuration.
- `lib/mix/tasks/phase5.knowledge.preflight.ex` — entry gate (§2a).

### New (Tooling)

- `mix phase5.knowledge.preflight` — validates `:embedding_adapter` ∈
  allowlist, dimension consistency, provider key presence when the
  configured embedder requires one, and (unless `--skip-network`) one
  low-cost embed call. Mirrors `phase4.ai.preflight`.

## 3. Ash resources

### 3.1 `Knowledge.Manual` (NEW)

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `title` | string | — | Operator-visible label. Max 200. |
| `slug` | string | — | Unique, URL-safe. |
| `body` | string | yes | Deployment knowledge. Max 64K chars. |
| `revision` | integer | — | Starts 1; +1 on every `:revise`. Drives chunk staleness. |
| `status` | atom | — | `:active \| :archived`. Default `:active`. |
| `created_at / updated_at` | utc_datetime_usec | — | |
| `deleted_at` | utc_datetime_usec | — | Soft-delete (ADR-019). |

Actions (intent verbs):

- `read` (primary): `filter(is_nil(deleted_at))`; admin + operator
  (operators read manuals as reference material). Viewer: none.
- `:author` (create): admin only. `accept [:title, :slug, :body]`.
  Change: `EnqueueIndexing`.
- `:revise` (update): admin only. `accept [:title, :body]`; bumps
  `revision` (+1, `require_atomic? false`); change `EnqueueIndexing`
  (skipped when only `title` changed — content hash decides).
- `:archive` / `:restore` (update): admin only; status flip. Archived
  manuals are excluded from retrieval (§4.1) but stay readable.
- `:soft_delete` (destroy → soft): admin only; sets `deleted_at`;
  excluded from read + retrieval.

Extensions: `AshPaperTrail` (body is sensitive → `:redact` mode like
Draft), policies as above. One Manual row per operational topic;
versioning = paper-trail + `revision` int (resolves the "snapshots vs
diffs" §13 question for *Manual*: snapshots via paper trail; Persona
stays as-is this phase — §12 Q8).

### 3.2 `Knowledge.ManualChunk` (NEW)

Derived data — rebuilt from Manual on revision; not paper-trailed.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `manual_id` | uuid FK | — | `on_delete: :delete` (derived rows follow the parent). |
| `revision` | integer | — | Manual.revision at staging time. |
| `position` | integer | — | 0-based chunk order. |
| `content` | string | yes | Chunk text (≤ ~2K chars). |
| `content_hash` | string | — | SHA-256 of content; skip re-embed when unchanged. |
| `embedding` | vector(1024) | — | Nullable until embedded. Dimension per §5. |
| `embedder` | string | — | e.g. `"fixture"`, `"voyage:voyage-3.5-lite"`. |
| `embedded_at` | utc_datetime_usec | — | |

Actions — all system-internal, gated by a `FromIndexingWorker` context
check (pattern: Phase 4 `FromGenerationWorker`):

- `read` (primary): admin only (inspection); the Retriever reads with
  `authorize?: false` inside the worker path.
- `:stage` (create, bulk): worker-only; rows for a new revision.
- `:stamp_embedding` (update): worker-only; writes vector + embedder +
  timestamp.
- `:prune_revisions` (destroy, hard): worker-only; deletes rows of
  superseded revisions *after* the new revision is fully embedded.
  Hard-delete is deliberate (ADR-019 exception): chunks are derived,
  reconstructible from Manual paper-trail versions; provenance stores
  `{manual_id, revision, position, content_hash}` which stays
  resolvable against version history even after pruning.

Indexes: `(manual_id, revision, position)` unique; HNSW (or IVFFlat)
index on `embedding` — hand-authored migration since ash_postgres does
not manage pgvector index types; `gin (content gin_trgm_ops)` for the
lexical fallback.

### 3.3 `Interaction.Draft` (MODIFIED)

New attribute `ai_retrieval` (`:map`, sensitive like `ai_prompt`):

```elixir
%{
  "mode" => "vector" | "lexical" | "none",
  "excerpts" => [
    %{"manual_id" => …, "manual_slug" => …, "revision" => 3,
      "position" => 2, "content_hash" => "…", "score" => 0.83,
      "embedder" => "voyage:voyage-3.5-lite"}
  ]
}
```

Excerpt *text* is not duplicated here — it already persists verbatim
inside `ai_prompt` (the assembled prompt JSON). Accepted only by
`:complete_generation` / `:fail_generation` (worker-gated); readable
under the existing AI-provenance policy (admin/operator, no viewer).

## 4. Subsystem detail

### 4.1 Retrieval ladder (`Knowledge.Retriever`)

```
retrieve(query_text, opts)
  1. config :retrieval enabled? == false      → {:ok, mode: :none}
  2. no embeddable chunks exist               → {:ok, mode: :none}
  3. embed query via configured Embedder
       ok → pgvector cosine top-k over active manuals' current
            revisions, min_score + token budget applied
            → {:ok, mode: :vector, excerpts}
       error (any class) →
  4. pg_trgm `similarity(content, query)` top-k
       ok  → {:ok, mode: :lexical, excerpts}
       error / empty → {:ok, mode: :none}
```

- Scope filter at every rung: manual `status == :active`,
  `is_nil(deleted_at)`, `chunk.revision == manual.revision`.
- Query text: the last inbound message body (bounded to 2K chars) —
  same context source the prompt already uses; no new sensitive
  surface.
- Defaults (config §5): `top_k: 4`, `min_score: 0.5`,
  `token_budget: 1_200`.
- The ladder **never raises into the worker**: every failure class
  degrades one rung; `mode` records what actually happened. AC
  "retrieval outage never hard-fails generation" hangs off this.
- Telemetry: `[:awd, :knowledge, :retrieval, :stop]`
  (measurements: duration, chunk_count; metadata: mode, draft_id).

### 4.2 Indexing pipeline (`ChunkAndEmbedWorker`)

Queue `:knowledge_indexing` (own queue — embedding latency must not
starve `:ai_generation` or `:outbound`). `max_attempts: 5`, backoff as
GenerationWorker.

```
perform(%{manual_id, revision})
  1. load Manual; revision stale (< current)?      → :ok (noop; a newer job exists)
  2. Chunker.chunk(body)                            → [%{position, content, hash}]
  3. diff against existing rows by content_hash     → reuse vector where hash matches
  4. :stage new rows; Embedder.embed(new contents)  → :stamp_embedding each
  5. :prune_revisions (< revision)                  → :ok
```

- Embed failures: `:transient`/`:rate_limited`/`:timeout` → raise (Oban
  retry); `:permanent` → leave chunks staged-but-unembedded (lexical
  fallback still works over them) + telemetry
  `[:awd, :knowledge, :indexing, :exception]`. Never blocks Manual
  authoring — the resource write already committed.
- Chunker: split on blank lines, greedy-merge to ≤ 1_600 chars, hard
  wrap oversized paragraphs; pure + property-testable (rebuild
  invariant: `Enum.join(chunks)` covers all non-whitespace content).

### 4.3 Prompt integration

`PromptAssembler.build/1` gains optional `retrieval:` input. Rendering:

- Cached blocks (framework, persona) stay byte-identical — cache
  markers untouched (Phase 4 AC on cache stability preserved).
- New system block appended *after* cached blocks, *before* messages:
  `"Deployment knowledge (retrieved excerpts — ground drafts in these
  when relevant):\n[manual-slug r3 §2] …content…"` — one line-header
  per excerpt so provenance is human-legible inside `ai_prompt`.
- No `cache_control` on the retrieval block (changes per query; caching
  it would thrash the prefix cache).
- Token budget enforced at Retriever level; assembler trims tail
  excerpts if the existing overall budget would overflow (reuses Phase
  4 trimming).

### 4.4 GenerationWorker changes

Between `build_prompt` and `run_adapter`:

```elixir
retrieval = Retriever.retrieve(query_text(messages), draft: draft.id)
prompt    = PromptAssembler.build(%{…, retrieval: retrieval})
…
persist_success(draft, prompt, response, validator, retrieval)
```

`persist_success` adds `ai_retrieval` to the `:complete_generation`
attrs; ChainLink reads it for the payload extension. Retrieval runs
*before* the provider call so a retrieval fallback is visible even when
generation later fails.

## 5. Configuration

```elixir
# config/config.exs (framework defaults)
config :ashy_walnut_desk, :embedding_adapter, AshyWalnutDesk.Knowledge.Embedders.Fixture
config :ashy_walnut_desk, :embedding_adapter_allowlist, [
  AshyWalnutDesk.Knowledge.Embedders.Fixture,
  AshyWalnutDesk.Knowledge.Embedders.Voyage
]
config :ashy_walnut_desk, :embedding_model, "voyage-3.5-lite"
config :ashy_walnut_desk, :embedding_model_allowlist, ["voyage-3.5-lite", "voyage-3.5"]
config :ashy_walnut_desk, :embedding_dimension, 1024
config :ashy_walnut_desk, :retrieval,
  enabled?: true, top_k: 4, min_score: 0.5, token_budget: 1_200
```

`config/runtime.exs` (prod): flips `:embedding_adapter` to `Voyage`
**only when** `VOYAGE_API_KEY` is present; otherwise stays `Fixture`?
No — silent fixture-in-prod is a lie. Resolution: prod requires an
explicit `EMBEDDING_ADAPTER` env (`voyage` | `none`); `none` runs
lexical/no-context retrieval only (the supported no-external-embedding
mode from requirements §3); `voyage` additionally requires
`VOYAGE_API_KEY` or boot raises. Unset `EMBEDDING_ADAPTER` ⇒ boot
raises with the two options spelled out. Deployer choice is always
explicit and auditable.

`:embedding_dimension` is fixed at migration time (vector(1024)); the
preflight cross-checks config vs column dimension and the Voyage model's
native dimension.

## 6. LiveView components

- `ManualLive.Index` — route `/manuals` (admin-only `live_session`
  mount, same policy chain as `/audit/chain`): list (title, slug,
  status, revision, embedded-state derived from chunk stats), archive/
  restore actions.
- `ManualLive.Form` — routes `/manuals/new`, `/manuals/:id/edit`
  (admin): `AshPhoenix.Form` over `:author`/`:revise` (distinct `as:`
  per the Phase 1 duplicate-id gotcha). Shows paper-trail version list
  read-only.
- `InboxLive` `GenerationPanel` (modified): per-candidate provenance
  badge — `data-role="retrieval-badge"`, text like
  `"knowledge: 3 excerpts (vector)"` / `"knowledge: none"` — gettext-
  backed; operators see *that and how* knowledge grounded a draft
  (resolved question Q5: operators get count+mode; full excerpt
  inspection is admin-side via `ai_prompt`).

## 7. Audit chain integration

No new event type. `:draft_generation_completed` payload allowlist
gains `retrieval_mode` (string) + `retrieval_chunk_count` (int) —
mirrors how validator fields ride that event. Chunk-level provenance
lives on `Draft.ai_retrieval` (admin-visible), not in the chain: chain
payloads stay small and hash-stable, and the chain already links to the
draft id for drill-down. `mix audit.verify` needs no change (allowlist
append only).

## 8. Data flow (generation with retrieval)

```
operator → Draft.:generate ─▶ Oban :ai_generation
  worker: load draft ─▶ Retriever.retrieve
            │  Embedder.embed(query)      (Fixture: pure; Voyage: HTTPS)
            │    ├─ ok  → pgvector top-k
            │    └─ err → pg_trgm top-k → or :none
            ▼
          PromptAssembler (cached blocks + retrieval block + messages)
            ▼
          AI.Adapter.complete  (Phase 4, unchanged)
            ▼
          Validator stack      (Phase 4, unchanged)
            ▼
          Draft.:complete_generation (+ ai_retrieval)
            ▼
          AuditEvent :draft_generation_completed
              (+ retrieval_mode, retrieval_chunk_count)
```

Approve/countdown/send: byte-for-byte the Phase 2–4 path.

## 9. External integrations

**Voyage AI embeddings** (reference impl; ADR-026):

- `POST https://api.voyageai.com/v1/embeddings`, bearer
  `VOYAGE_API_KEY`, body `{model, input: [texts], input_type:
  "document" | "query"}`.
- Error classification mirrors the Anthropic adapter: 429 →
  `:rate_limited`, 5xx → `:transient`, 400 → `:permanent`, 401/403 →
  `:permanent`, transport timeout → `:timeout`.
- Test injection: `:voyage_req_options` (Req plug), same pattern as
  `:anthropic_req_options` / `:twilio_req_options`.
- Rate/size limits: batch ≤ 128 texts per call (worker batches chunk
  embeds); retrieval-time query embed is a single-text call.
- Key handling: env-only, never logged, never persisted (AGENTS.md
  §7.4); `sensitive?` not applicable (no resource field ever carries
  it).

**Fixture embedder**: hashed bag-of-words → 1024-dim unit vector
(token → bucket via `:erlang.phash2`, count-weighted, L2-normalized).
Deterministic, order-insensitive, and similar texts share buckets — so
ranking assertions in tests are stable and meaningful without any
network. Dev default; also the CI embedder.

## 10. Migration plan

1. Hand-authored: none needed for extensions (`vector`, `pg_trgm`
   enabled since Phase 0 — `20260512150000_enable_extensions.exs`).
2. Generated (`mix ash_postgres.generate_migrations`): `manuals`,
   `manual_chunks` tables. The `embedding vector(1024)` column and the
   HNSW + trgm indexes go in a hand-authored follow-up migration
   (ash_postgres has no first-class pgvector index DSL; snapshot files
   record the column as `:vector` custom type via `AshPostgres.Extensions.Vector`
   if available — Architect note: if the installed ash_postgres version
   lacks vector-type support, model `embedding` as a custom
   `Postgrex`-typed attribute with a hand-authored column, mirroring
   the "hand-author over fighting the generator" gotcha).
3. Rollback: drop `manual_chunks` then `manuals`; Draft `ai_retrieval`
   is additive/nullable; audit payload keys are additive. Phase 4
   behavior restores by config: `:retrieval, enabled?: false`.

## 11. Failure modes

| Failure | Degradation |
|---|---|
| Embedding provider down at index time | Oban retries; chunks staged unembedded; lexical fallback serves them |
| Embedding provider down at query time | rung 4: pg_trgm lexical; mode recorded |
| pgvector index corrupt/missing | rung 4 (architecture §10 project-level promise) |
| No manuals / all archived | mode `:none`; generation proceeds context-free, badge says so |
| Oversized manual body | chunker hard-caps; `:author`/`:revise` validates ≤ 64K chars |
| Indexing job storm on bulk edits | per-manual jobs, content-hash dedupe, dedicated queue |
| Stale chunks (old revision) after failed prune | retrieval filters `chunk.revision == manual.revision`; prune retries |

## 12. Resolved open questions (from requirements §7)

- **Q1 embedding provider** → Behaviour + Fixture + Voyage reference
  impl; prod adapter choice is an explicit env decision incl. a
  supported `none` mode (ADR-026).
- **Q2 Persona embedded?** → No. Persona stays prompt-only; roadmap's
  "Manual/Persona content" is satisfied by Persona *already being in
  the prompt* and Manual gaining retrieval. Revisit only if excerpt
  quality shows persona-content gaps.
- **Q3 retrieval budget** → framework defaults `top_k 4 / min_score
  0.5 / token_budget 1200`, deployment-overridable via config (§5).
- **Q4 provenance event** → payload extension on
  `:draft_generation_completed`; no new event type (§7).
- **Q5 operator visibility** → count+mode badge for operators; full
  excerpt text via admin `ai_prompt` inspection (§6).
- **Q6 Guardrail resource** → not this phase; Persona
  `guardrail_notes` + deployment validators still suffice (requirements
  out-of-scope holds).
- **Q7 multi-tenant evidence** → telemetry counters (retrieval volume,
  chunk counts, per-deployment index size) land in this phase; the
  decision itself stays at phase end (unchanged).
- **Q8 Persona versioning** → unchanged this phase (paper-trail
  snapshots already exist); Manual takes the same snapshot posture
  (§3.1). The architecture §13 question can be closed as "snapshots"
  at phase retro.

## 13. Security & safety review

- **Sensitive flows**: Manual bodies (deployment knowledge) →
  embedding provider (Voyage) when explicitly configured. Surfaced in
  runbook + the `EMBEDDING_ADAPTER=none` escape hatch. Chunk content
  `sensitive? true`; excerpts reach `ai_prompt` which is already
  sensitive + policy-gated.
- **Identity-axis PII**: never embedded — only Manual content enters
  the index; query text is the inbound message (already in prompts);
  tests assert no Identity fields in embed payloads (mirrors Phase 4
  prompt-exclusion tests).
- **AI output to end users**: unchanged path; retrieval adds context
  in, not output out. Validator + approval + countdown gates untouched
  and regression-tested with retrieval active.
- **Audit**: Manual writes paper-trailed; generation provenance on
  Draft + chain payload; no raw content in chain payloads.
- **AuthZ**: Manual admin-write/operator-read/viewer-none; ManualChunk
  internal; LV routes admin-gated.

## 14. Testing strategy

- **Unit**: Chunker (incl. property: coverage + determinism + hash
  stability), Fixture embedder (determinism, normalization,
  similar-text bucketing), Voyage adapter (Req plug: envelope, error
  classes, batch), Retriever ladder (each rung + scope filters),
  PromptAssembler retrieval block (cache-marker stability).
- **Integration**: Manual authoring LV (admin/operator/viewer policy
  matrix), indexing worker end-to-end vs sandbox (drain
  `:knowledge_indexing`), generation e2e with retrieval active
  (extends the Phase 4 e2e: badge + `ai_retrieval` + payload keys),
  regression: full Phase 4 chain with `:retrieval enabled?: false`.
- **Property-based**: chunk rebuild invariant; retrieval scope
  invariant (never returns archived/deleted/stale-revision chunks).
- **Manual (human)**: excerpt relevance quality; runbook walkthrough
  against a real Voyage key.

## 15. ADRs introduced

- **ADR-026** — Embeddings via a pluggable `Knowledge.Embedder`
  behaviour; Voyage AI as the Req-direct reference implementation;
  explicit `EMBEDDING_ADAPTER` prod choice including `none`.
  (Anthropic's Messages API ships no embeddings endpoint — a second
  provider is unavoidable; the behaviour keeps it swappable and the
  Fixture keeps CI/dev offline.)

## 16. Story-breakdown hints for PM

- Manual resource + policies + paper-trail + migrations.
- Chunker + ManualChunk + indexing worker against Fixture embedder.
- Embedder behaviour + Fixture + Voyage impl + allowlist + conformance.
- Retriever ladder + config + telemetry.
- PromptAssembler/GenerationWorker integration + `ai_retrieval` +
  audit payload extension.
- Manual admin LV + generation-panel badge + gettext.
- Phase 5 preflight + deployer runbook + integration/regression gate.

Constraint per AGENTS.md §2: each story 1–3h, fresh session, spec is
the bridge.
