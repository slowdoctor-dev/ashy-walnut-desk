# Story 5.5: Generation integration — retrieval block, ai_retrieval provenance, audit payload

**Phase**: 5
**Estimate**: 3h
**Depends on**: 5.4
**Status**: ready

---

## Goal

Wire retrieval into the Phase 4 generation path: PromptAssembler
renders retrieved excerpts as a non-cached system block,
GenerationWorker persists `Draft.ai_retrieval`, and
`:draft_generation_completed` carries `retrieval_mode` +
`retrieval_chunk_count`.

## Context

The integration story that makes RAG real; everything upstream (5.1–
5.4) exists to feed this. Cache-marker stability and chain-hash
compatibility are the two regression hazards.

## Reference specs

- `/specs/phase-5/architecture.md` §3.3 (`ai_retrieval`), §4.3, §4.4, §7 (audit)
- `/specs/phase-4/architecture.md` §4 (assembler/worker baseline)

## Acceptance criteria

- [ ] AC1: `PromptAssembler.build/1` accepts `retrieval:`; excerpts render as one appended system block with `[manual-slug rN §pos]` headers, after cached blocks, without `cache_control`; cached framework/persona blocks stay byte-identical with and without retrieval. — Verify: `mix test test/ashy_walnut_desk/ai/prompt_assembler_retrieval_test.exs`
- [ ] AC2: GenerationWorker calls `Retriever.retrieve/2` before assembly and persists `ai_retrieval` (mode + excerpt provenance, no excerpt text) via `:complete_generation`; worker-only accept, sensitive policy identical to `ai_prompt`. — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_retrieval_test.exs`
- [ ] AC3: `:draft_generation_completed` payload allowlist gains `retrieval_mode`/`retrieval_chunk_count`; chain hashing stays verifiable (`AuditChain.walk` + `mix audit.verify` green over a retrieval-active chain). — Verify: `mix test test/ashy_walnut_desk/interaction/draft_generation_audit_chain_test.exs`
- [ ] AC4: With `:retrieval enabled?: false`, generation output and audit payloads are byte-compatible with Phase 4 behavior (mode `:none`, zero count) — regression pin. — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_test.exs`

## Files to create

```
test/ashy_walnut_desk/ai/prompt_assembler_retrieval_test.exs
test/ashy_walnut_desk/ai/jobs/generation_worker_retrieval_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/ai/prompt_assembler.ex                       — retrieval block
lib/ashy_walnut_desk/ai/jobs/generation_worker.ex                 — retrieve + persist
lib/ashy_walnut_desk/interaction/draft.ex                         — ai_retrieval attr + accepts
lib/ashy_walnut_desk/interaction/changes/chain_link.ex            — payload fields
lib/ashy_walnut_desk/interaction/audit_chain.ex                   — allowlist extension
priv/repo/migrations/<ts>_add_draft_ai_retrieval.exs              — generated
test/ashy_walnut_desk/interaction/draft_generation_audit_chain_test.exs — extend
```

## Implementation notes

Retrieval runs before the provider call so fallback mode is recorded
even on generation failure (architecture §4.4). Existing payload
canonicalization treats new keys as additive — extend
`@payload_allowlist` only; never reorder existing keys.

## Safety review

- Sensitive records touched? yes — ai_prompt now embeds Manual excerpts; ai_retrieval sensitive like ai_prompt
- AI output to end user possible? yes — retrieval-grounded drafts flow to the existing approval path
- Guardrails applied? validator gate unchanged and asserted; no new send path
- Audit trail covered? chain payload extension + Draft provenance

## Out of scope (will NOT do in this story)

- Operator badge / LV changes (5.6), preflight + docs (5.7)

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/ai/ test/ashy_walnut_desk/interaction/
mix audit.verify
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
