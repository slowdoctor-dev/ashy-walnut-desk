# ADR-026: Embeddings via a pluggable Knowledge.Embedder behaviour (Voyage AI reference impl)

**Status**: Accepted
**Date**: 2026-07-11
**Deciders**: solo maintainer

---

## Context

Phase 5 grounds AI drafts in deployment-authored `Manual` content via
pgvector similarity retrieval (BASELINE §7 roadmap line). Retrieval
requires text embeddings — and the provider the framework already
integrates for generation, Anthropic (ADR-004/ADR-025), ships **no
embeddings endpoint** on its Messages API. Some second embedding source
is unavoidable.

Constraints:

- The stack rule "Anthropic API direct via Req, no Python service"
  (ADR-004) implies any embedding provider is likewise Req-direct.
- CI and dev must run fully offline (Phase 4 precedent: Fixture
  adapter is the non-prod default; deterministic tests).
- Manual bodies are deployment knowledge and potentially sensitive —
  sending them to a third party must be an explicit, auditable
  deployer decision, and refusing external embedding must remain a
  supported configuration (requirements §3 safety scope).
- Framework must stay provider-agnostic per ADR-006 (domain and vendor
  choices are deployment configuration, not forks).

## Options considered

### Option 1: Pluggable `Knowledge.Embedder` behaviour + Fixture + Voyage AI reference impl

Mirror the Phase 3/4 adapter pattern a third time: a small behaviour
(`embed(texts, opts)`), a deterministic no-network `Fixture`
(test/dev default), and one Req-direct HTTP reference implementation.
Voyage AI is the reference because it is Anthropic's recommended
embeddings partner and its API shape (batch input, model families with
1024-dim defaults) fits the chunk pipeline.

- Pros: consistent with `Interaction.Adapter` (ADR-022) and
  `AI.Adapter` (ADR-025) — one pattern to learn; offline CI preserved;
  provider swap = one module + allowlist entry; explicit error-class
  contract reuses the Phase 4 taxonomy.
- Cons: a second external account for deployers who want vector
  retrieval; one more behaviour to conformance-test.

### Option 2: Postgres-internal embeddings (no external provider)

Use lexical statistics only (pg_trgm / tsvector) or an in-database
embedding extension; no vector semantics from a model.

- Pros: zero external dependency; no knowledge leaves the deployment.
- Cons: abandons the roadmap's pgvector RAG semantics — trigram overlap
  is not semantic similarity; retrieval quality ceiling is low;
  pgvector column becomes pointless. Rejected as the *only* mode, but
  retained as the fallback rung and as the supported
  `EMBEDDING_ADAPTER=none` posture.

### Option 3: Self-hosted embedding model (e.g. ONNX/Bumblebee in-BEAM)

Run an open embedding model inside the deployment (Bumblebee/Nx or a
sidecar).

- Pros: no data leaves the deployment; no per-call cost.
- Cons: heavyweight runtime dependency (model weights, native
  backends) contradicting the lean single-instance posture (ADR-012);
  operational burden lands on a solo maintainer; the behaviour
  boundary from Option 1 already leaves this open as a future
  `Embedders.Local` without deciding it now.

## Decision

We chose **Option 1: pluggable `Knowledge.Embedder` behaviour with a
deterministic Fixture and a Req-direct Voyage AI reference
implementation** — with two riders:

- **Prod adapter choice is explicit**: `config/runtime.exs` requires
  `EMBEDDING_ADAPTER` to be set to `voyage` (plus `VOYAGE_API_KEY`) or
  `none`; an unset value fails boot. No silent fixture-in-prod, no
  silent data egress.
- **`none` is first-class**: retrieval degrades to the pg_trgm lexical
  rung (Option 2 behavior) and generation continues context-free when
  even that yields nothing — retrieval never blocks drafting.

Reasoning:

- Third instance of a proven in-repo pattern (ADR-022, ADR-025):
  behaviour + fixture + allowlist + Req plug test injection.
- Keeps the safety posture honest: external embedding is opt-in and
  auditable; the no-egress mode is tested, not theoretical.
- Leaves provider evolution (self-hosted, other vendors) as a
  single-module addition, per ADR-006.

## Consequences

### Positive

- CI/dev remain fully offline (Fixture); retrieval ranking is
  deterministic in tests.
- Deployers pick their embedding posture explicitly; the runbook can
  document exactly two prod paths.
- Error taxonomy (`:transient | :permanent | :rate_limited |
  :timeout`) is shared with Phase 4, so worker retry semantics are
  uniform.

### Negative / accepted trade-offs

- A second provider account (and data-processing review) for
  vector-mode deployments.
- Fixture similarity is lexical-ish (hashed bag-of-words), so
  retrieval-quality assertions in tests are structural, not semantic.
- 1024-dim column fixed at migration time; changing dimension is a
  migration + re-embed event.

### Follow-up actions

- [ ] Story: behaviour + Fixture + Voyage impl + conformance suite.
- [ ] Preflight (`mix phase5.knowledge.preflight`) validates adapter
      allowlist, dimension consistency, key presence, `--skip-network`.
- [ ] Runbook documents `EMBEDDING_ADAPTER=voyage|none` and the
      data-egress implications of `voyage`.

## References

- Related ADRs: ADR-004, ADR-006, ADR-012, ADR-022, ADR-025
- `specs/phase-5/requirements.md` §5 (external dependencies), §7 (Q1)
- `specs/phase-5/architecture.md` §2, §5, §9
- External: Voyage AI embeddings API (`POST /v1/embeddings`)
