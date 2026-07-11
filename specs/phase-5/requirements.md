# Phase 5 — Requirements

## 1. Goal

Deliver the Knowledge-axis operational layer — deployment-authored Manual
content with retrieval-augmented draft generation — so AI drafts are
grounded in deployment-approved knowledge with full retrieval provenance,
without weakening any Phase 2–4 approval/countdown/audit invariant.

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 5 stories merge.
- [ ] Admin can author, revise, archive, and restore `Manual` content through named Ash actions only; Manuals are soft-deleted and paper-trailed (versioned, never hard-deleted — architecture §8.8).
- [ ] Manual content is chunked and embedded for similarity retrieval; chunking/embedding runs as background jobs (never in the operator request path) and re-runs automatically when a Manual revision changes retrievable content.
- [ ] Draft generation prompt assembly can include retrieved Manual excerpts scoped to the deployment's active (non-archived, non-deleted) Manual versions only.
- [ ] Retrieval is deterministic under test: a fixture embedding source exists so retrieval ranking is reproducible without any network call.
- [ ] Retrieval provenance persists per generation attempt: which chunks (Manual id + version + chunk ref + similarity score) entered the prompt, admin-visible under existing sensitive-field policies and reflected in the audit chain.
- [ ] Retrieval degrades gracefully: when vector search is unavailable or under-populated, generation proceeds via the documented fallback (lexical `pg_trgm` match, or explicitly-marked no-context generation); a retrieval outage alone never hard-fails generation and never blocks manual drafting.
- [ ] Secrets/credentials and Identity-axis sensitive identifiers never enter embedding payloads, the vector index, or retrieved excerpts (test-enforced exclusion, mirroring Phase 4 prompt-assembly exclusions).
- [ ] The embedding provider sits behind an adapter boundary with a configured allowlist (mirroring `:ai_adapter` / `:channel_adapters`); no provider-specific types leak into Knowledge-axis business logic.
- [ ] Knowledge retrieval introduces no new send path: human approval + 5-second countdown + hash-chained audit remain regression-tested end to end with retrieval active.
- [ ] Validator behavior is unchanged or strengthened: retrieved content cannot cause a draft to bypass `Safety.Validator` outcomes, and guardrail content remains deployment-configured (no hardcoded domain claims).
- [ ] All new operator/admin-facing strings are gettext-backed.
- [ ] A Phase 5 preflight gate exists (new task or extension) that fails fast on missing/invalid embedding-provider configuration, with an offline `--skip-network` mode.

## 3. Scope

### In scope

- `Manual` resource (Knowledge domain) with authoring lifecycle, policies, soft-delete, paper-trail.
- Chunking + embedding pipeline as Oban background work with re-embedding on revision.
- pgvector-backed similarity retrieval over Manual content, with `pg_trgm` lexical fallback per architecture §10.
- Prompt-assembly integration: retrieved excerpts enter the existing Phase 4 prompt structure (persona block untouched; retrieval gets its own context block with stable cache posture).
- Retrieval provenance persistence + audit-chain visibility.
- Embedding-provider adapter boundary, config allowlist, fixture implementation for tests.
- Admin LiveView surface for Manual authoring and retrieval inspection (minimum viable: list/edit/version history).
- Phase 5 preflight + deployer runbook documentation.
- Regression protection for all Phase 2–4 invariants with retrieval enabled.

Safety implications in scope:

- Manual content is deployment knowledge, potentially sensitive — embedding sends it to a third-party provider; the cross-border/data-processing decision must be surfaced to deployers (per `specs/compliance/` posture), and the framework must support refusing external embedding (fallback-only mode).
- Retrieved excerpts can smuggle unsafe domain assertions into drafts — validator gate stays mandatory and retrieval provenance makes the source traceable.
- Retrieval failures must degrade, never bypass: no cached/stale content presented as fresh without version provenance.

### Out of scope

- `Vault` (domain knowledge package) and `Guardrail` as standalone resources beyond what Phase 4's Persona/guardrail-notes + validator config already provide (defer to a later phase unless the Architect finds a hard dependency).
- Multi-tenant partitioning redesign (architecture §13 — decision point is *end* of Phase 5, informed by this phase's learnings; the decision itself is not a Phase 5 deliverable).
- Real-time AI streaming UX.
- New channel adapters or provider integrations outside embeddings.
- Autonomous send, auto-approval, countdown changes (inviolable).
- Cross-deployment knowledge sharing or marketplace concepts.
- Retrieval quality analytics dashboards beyond basic telemetry counters.

## 4. Story breakdown (filled later by PM)

| # | Story | Estimate | Depends on | Status |
|---|---|---|---|---|
| 5.1 | Manual resource foundation (Knowledge axis) | 3h | — | done |
| 5.2 | Embedder behaviour + Fixture + Voyage adapter + conformance | 3h | — | done |
| 5.3 | Chunker + ManualChunk resource + indexing worker | 3h | 5.1, 5.2 | done |
| 5.4 | Retriever ladder (vector → lexical → none) + telemetry | 3h | 5.3 | done |
| 5.5 | Generation integration — retrieval block + provenance + audit payload | 3h | 5.4 | done |
| 5.6 | Manual admin LiveView + generation-panel retrieval badge | 3h | 5.1, 5.5 | done |
| 5.7 | Phase 5 preflight + deployer docs + integration/regression gate | 3h | 5.1–5.6 | done |

Parallel tracks: 5.1 and 5.2 are independent starters; critical path is
5.2 → 5.3 → 5.4 → 5.5 → 5.7.

## 5. Dependencies

### External

- An embedding provider account: the Anthropic Messages API used in Phase 4 does **not** provide an embeddings endpoint, so a second provider (e.g., Voyage AI — Anthropic's recommended embeddings partner — or an equivalent) or a deployer-hosted embedding model is required.
- Deployer decision on sending Manual content to that provider (data-processing agreement, cross-border posture per `specs/compliance/`).
- Postgres extensions `vector` (pgvector) and `pg_trgm` available in the deployment database (already required by the stack, BASELINE §5).

### Internal

- Phase 4 AI subsystem (adapter boundary, prompt assembler, validator stack, generation worker, audit events) as the integration surface.
- Phase 2/3 chain semantics and audit-chain event registry (payload allowlist will need new event types or payload extensions).
- Knowledge domain + Persona resource (Phase 4) as the domain home for Manual.

## 6. Risks

- Retrieval quality is unmeasurable at first — poor chunking or thresholds could inject irrelevant context and degrade drafts.
  - Mitigation: deterministic fixture-based ranking tests + telemetry on retrieval hit/score distribution + operator-visible provenance for spot checks.
- Embedding a Manual revision lags its publication, serving stale knowledge.
  - Mitigation: version-stamped provenance, automatic re-embed jobs on revision, and AC-tested staleness marking in fallback paths.
- Third-party embedding leaks sensitive deployment knowledge.
  - Mitigation: sensitive-field exclusion tests, deployer-facing runbook warning, and a supported no-external-embedding fallback mode.
- Vector index corruption or extension unavailability breaks generation.
  - Mitigation: `pg_trgm`/no-context fallback is a phase-level AC, not an afterthought.
- Cost creep: re-embedding large Manual sets on every edit.
  - Mitigation: chunk-level content hashing so only changed chunks re-embed; telemetry on embedding volume.
- Scope creep into Vault/Guardrail resource design.
  - Mitigation: explicit out-of-scope listing above; Architect must justify any pull-forward.

## 7. Open questions

- Which embedding provider does the reference deployment use, and is a deployer-hosted (local) embedding model a launch requirement or a later option?
- Is Persona content also embedded/retrievable (the roadmap line says "Manual/Persona content"), or does Persona remain prompt-only as in Phase 4?
- What retrieval budget enters the prompt (top-k, score threshold, token ceiling) and who tunes it — framework default with deployment override?
- Does retrieval provenance become a new audit-chain event type or a payload extension of `:draft_generation_requested/_completed`?
- Do operators see retrieved excerpts in the generation panel (transparency) or only admins via provenance inspection (simplicity)?
- Guardrail content: does Phase 5 need a first-class `Guardrail` resource, or do Persona `guardrail_notes` + deployment validators still suffice?
- Multi-tenant question (architecture §13) is decided at Phase 5 end — what evidence should this phase collect to inform it?
- Persona versioning: full snapshots or diffs (architecture §13, deferred to Phase 5)?
