# ADR-025: Req-direct Anthropic via internal AI.Adapter behaviour (not ash_ai)

**Status**: Accepted
**Date**: 2026-05-20
**Deciders**: solo maintainer

---

## Context

Phase 4 introduces AI draft generation. The framework needs a
provider-call boundary that (a) emits stable Anthropic prompt-caching
markers (per requirements §2 + CLAUDE.md gotcha on `cache_control`),
(b) carries full provenance into the existing `Draft.ai_*` fields,
(c) is swappable for a deterministic test fixture, and (d) preserves
the safety invariants — Validator-gated output, no autonomous send,
audit chain unbroken.

AGENTS.md §4 lists `ash_ai` among the Ash extensions in scope. Phase 4
must decide whether to call Anthropic through `ash_ai` primitives or
through a thin in-repo adapter, mirroring the
`Interaction.Adapter` pattern Phase 3 hardened (ADR-022).

ADR-004 (Anthropic direct) decided at framework-baseline that there is
no separate Python service in the path; this ADR resolves the
next-finer-grained question of which Elixir-side surface holds the
call.

## Options considered

### Option 1: `ash_ai` as the AI call site

Call `ash_ai`'s prompt/tool primitives from generation code paths.
Provenance lands wherever `ash_ai` writes it; cache control flows
through whichever API `ash_ai` exposes.

- **Pros**: integrates with the rest of the Ash extension stack;
  potentially benefits from future ash_ai features (tool use, streaming,
  multi-turn) without re-implementation.
- **Cons**: `ash_ai` is a moving target (pre-1.0; API churn likely
  through 2026); validator gating and `cache_control` placement become
  dependent on `ash_ai`'s evolving abstractions; Phase 4 ships under
  safety-critical constraints (AGENTS.md §7.1) and cannot tolerate
  upstream-API drift; bug surface includes `ash_ai`'s prompt
  serialization, which is harder to audit than direct Anthropic JSON.

### Option 2: Direct `Anthropic` SDK call from Draft/worker code

Call Anthropic's elixir SDK (or `Req` directly) inline in the worker —
no behaviour, no abstraction. Each new provider would touch the worker.

- **Pros**: minimum indirection; obvious call site.
- **Cons**: no test fixture seam (CI either hits Anthropic or skips
  tests); a future Sonnet/Opus model swap, or a second provider
  (Bedrock/OpenAI for regions where Anthropic is restricted), forces
  re-architecture; the codebase already established the Adapter pattern
  in Phase 3 — inconsistent shape here taxes maintainability.

### Option 3: Internal `AshyWalnutDesk.AI.Adapter` behaviour, Req-direct impl

Mirror the Phase 3 `Interaction.Adapter` pattern. Define
`AI.Adapter.complete/2` callback. Real impl `AI.Adapters.Anthropic`
calls `Req.post` against `https://api.anthropic.com/v1/messages` with
explicit `cache_control` markers on stable blocks. Test impl
`AI.Adapters.Fixture` returns deterministic canned responses keyed on
prompt hash. Configuration selects impl per environment via
Application env, same allowlist mechanic as channel adapters.

- **Pros**: coherent with existing Phase 3 pattern (same allowlist,
  same test-fixture story, same conformance-test style); full control
  over JSON envelope including `cache_control` placement; clean fixture
  seam for CI; isolates Anthropic version churn behind one module;
  easy to add a second provider in a later phase without touching call
  sites.
- **Cons**: a small amount of extra code (~120 lines for the
  Anthropic impl + ~60 for the Fixture); we re-implement bits that
  `ash_ai` would have given us if its API stabilized.

## Decision

We chose **Option 3: Internal `AI.Adapter` behaviour, Req-direct
Anthropic implementation**.

Reasoning:
- Safety-critical surface needs auditable JSON envelopes and
  predictable behavior across upgrades; Anthropic's HTTP API is more
  stable than `ash_ai`'s 0.x abstractions in 2026.
- Pattern coherence with Phase 3 (`Interaction.Adapter`,
  `Adapters.Twilio`, `Adapters.Echo`, allowlist + conformance suite)
  reduces cognitive load and reuses Phase 3 conformance testing
  scaffolds.
- `cache_control` placement is load-bearing for Phase 4 cost — direct
  control beats relying on a wrapper to do the right thing.
- A test-fixture impl is a hard requirement for CI (we cannot call
  Anthropic from CI on every commit); a behaviour gives us that for
  free.
- Door stays open: if `ash_ai` stabilizes by Season 2, a future ADR
  can supersede this one by introducing an `AI.Adapters.AshAi` impl
  that satisfies the same behaviour, with zero churn at call sites.

## Consequences

### Positive

- One audited HTTP envelope per call; `cache_control` markers are
  explicit and grep-able.
- CI runs against `AI.Adapters.Fixture` with deterministic latency
  (configurable sleep) and prompt-hash-keyed canned responses; zero
  external dependency in the default test path.
- The `AI.Adapter` conformance suite (Phase 4 story) parallels Phase
  3's adapter conformance, raising provider-swap quality bars.
- New providers (Bedrock, OpenAI-compat fallback, on-prem inference)
  add as a single file + allowlist entry — no worker changes.

### Negative / accepted trade-offs

- No automatic upgrade path when `ash_ai` adds features (tool use,
  caching helpers, streaming). We carry that cost ourselves.
- `Req` response decoding for Anthropic streaming responses (if Phase
  6+ enables streaming) lands in our code, not a library's.
- A small duplication with Phase 3's adapter pattern (two behaviours,
  one shape) — accepted in exchange for axis separation (channel I/O
  vs. AI I/O are not the same domain even if they look alike).

### Follow-up actions

- [ ] Phase 4 ships `AI.Adapter` behaviour + `Anthropic` impl +
      `Fixture` impl + conformance test suite.
- [ ] Phase 4 telemetry events emit per-call latency, input/output
      token counts, and cache-read/cache-creation token counts so the
      cache-control choice can be evaluated empirically.
- [ ] Revisit at Season 2 retrospective: if `ash_ai` has stabilized,
      consider a `AI.Adapters.AshAi` impl as a parallel option.

## References

- Related ADRs: ADR-004 (Anthropic direct), ADR-022 (Twilio as first
  real channel adapter — pattern source), ADR-023 (Oban for outbound
  retry — Phase 4 mirrors the worker pattern for generation).
- External:
  - Anthropic Messages API: `POST https://api.anthropic.com/v1/messages`
  - Anthropic prompt caching: `cache_control: %{type: "ephemeral"}`
    markers on `content` blocks (GA — no beta header). Minimum
    cacheable prefix is model-dependent: ~2048 tokens on Sonnet 4.6,
    ~4096 on Opus 4.7 (corrected in story 4.3; an earlier "~1024"
    figure was wrong).
