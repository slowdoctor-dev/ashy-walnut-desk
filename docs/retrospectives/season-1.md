# Season 1 Retrospective — Phases 0–5

**Date**: 2026-07-11
**Scope**: everything from `mix phx.new` to the Phase 5 close
(BASELINE §7 roadmap complete).

---

## 1. What shipped

| Phase | Deliverable | Key ADRs |
|---|---|---|
| 0 | Phoenix + Ash scaffold, magic-link auth, audit + i18n foundations, CI gates | 001–015 |
| 1 | Identity axis: Identity/Event/Appointment/Note, policies, soft-delete, paper-trail, LV surface, token expunge | 019, 020 |
| 2 | Interaction axis: four-stage chain (Inbox→Draft→Action→Compensation), hash-chained AuditEvents + `mix audit.verify`, server-side 5s countdown, InboxLive | 016, 020, 021 |
| 3 | Twilio SMS adapter: signature-verified intake, Oban outbound retry, adapter conformance suite, `phase3.webhook.preflight` | 022–024 |
| 4 | AI drafts: Persona, Req-direct Anthropic adapter + model allowlist, validator stack, GenerationWorker + telemetry, generation UX, `phase4.ai.preflight` | 025 |
| 5 | Knowledge/RAG: Manual + chunk/embed pipeline, Embedder boundary (Fixture/Voyage/none), retrieval ladder (vector→lexical→none), grounded generation with provenance, `/manuals` LV, `phase5.knowledge.preflight` | 026 |

Inviolable invariants held through every phase and are pinned by
end-to-end gates per phase 3/4/5: **no autonomous send, 5-second
countdown, hash-chained audit on every transition**.

## 2. What worked

- **SDD with BMAD/GSD.** Spec-as-bridge survived many fresh AI
  sessions across two different agents (Claude, Codex). Story files
  with executable "Verify" blocks were the single highest-leverage
  convention: every AC maps to a command a machine can run.
- **Phase-gate stories (N.8/N.7 pattern).** Ending each phase with
  preflight + runbook + e2e/regression gate caught composition bugs
  that unit-level stories could not (e.g. Postgrex vector types, prod
  env contracts).
- **Adapter boundaries + allowlists.** The same shape three times
  (channel adapters, AI adapter, embedder) kept provider swaps
  config-only and made "no external provider" a first-class posture
  (`EMBEDDING_ADAPTER=none`).
- **CI as the only verifier.** Sandboxed agent environments could not
  run `mix` locally (hex.pm egress blocked). The workflow that emerged
  — `workflow_dispatch` verify runs plus a dispatch-only codegen job
  that emits migrations/snapshots/gettext as a base64 tarball in the
  log — turned CI into a remote pair of hands. Round-trips per story:
  typically 1–2.

## 3. What hurt (and what we changed)

- **Generated artifacts need a generator.** Ash migrations, resource
  snapshots, and gettext extraction cannot be hand-authored safely.
  Fix: the ci.yml codegen job (commit `1d9d34f`); outputs are committed
  byte-exact.
- **pgvector needed manual type registration.** 22 test failures from
  one cause: Postgrex has no built-in `vector` type. Fix:
  `AshyWalnutDesk.PostgrexTypes` + repo `types:` config; recorded in
  story 5.3 notes.
- **Prod boot contracts and tests must move together.** Adding the
  `EMBEDDING_ADAPTER` boot raise broke three runtime-config tests that
  didn't know the new variable. The contract tests now pin all three
  postures (unset / voyage / none).
- **AGENTS.md is at its 300-line cap.** New gotchas now displace old
  ones; per-story "Notes during implementation" absorbed the overflow
  this season. A future pass should promote stable gotchas into
  `docs/` and keep §10 for live traps.

## 4. Deferred decisions — resolved at this boundary

- **Multi-tenancy** → **ADR-027 (Proposed)**: stay single-tenant
  (one deployment = one instance) through Season 2, with explicit
  revisit triggers.
- **Persona versioning** → **ADR-028 (Proposed)**: keep
  `:changes_only` paper-trail diffs; generation-time provenance is
  owned by `Draft.ai_prompt` / `Draft.ai_retrieval`, never by version
  history.
- **LiveView AI streaming** (architecture §13, from Phase 4): still
  open — carried as a Season 2 candidate, not blocking anything.

Trade-off ledger: TO-14 (audit-chain admin viewer) was actually
resolved by story 3.7 and is now marked so. 10 trade-offs remain
active-accepted; TO-11 (viewer role reads sensitive Draft text) is the
one most worth a dedicated story early in any Season 2.

## 5. Season 2 candidates (possibilities, not commitments — ADR-018)

In rough value order for the target deployer:

1. **Consent resource** — the planned versioned-consent pattern
   (phase-1 architecture §3.5) never found its consumer phase.
2. **Viewer-role field-policy tightening** (TO-11) + a policy
   regression suite.
3. **Second real channel adapter** (email via SMTP/API) to prove the
   adapter boundary against a non-SMS shape.
4. **Retrieval quality iteration** — telemetry-driven top_k/min_score
   tuning, chunking by headings, per-Persona retrieval budgets.
5. **Overview layer** (read-only aggregation across axes) and
   meta-ops surfaces.
6. **LiveView streaming feasibility study** (open §13 item).
7. **`ash_ai` adapter implementation** behind the existing `AI.Adapter`
   boundary, when upstream stabilizes (ADR-025 follow-up).

None of these start without a Season 2 BMAD pass.

---

*Next boundary: owner review of ADR-027/ADR-028 (Proposed → Accepted)
and a go/no-go on Season 2 scope.*
