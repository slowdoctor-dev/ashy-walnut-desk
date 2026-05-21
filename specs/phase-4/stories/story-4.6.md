# Story 4.6: Oban Generation Worker Orchestration + Telemetry + Failure Semantics

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.3, 4.4, 4.5
**Status**: done

---

## Goal

Implement `AI.GenerationWorker` to orchestrate end-to-end generation (assemble -> complete -> validate -> persist -> transition) with deterministic failure semantics and telemetry.

## Context

This story activates the runtime pipeline while keeping send-path invariants unchanged. It must be idempotent, auditable, and non-blocking for LiveView.

## Reference specs

- `/AGENTS.md` §7 safety rules, §10 gotchas (Oban trigger/testing shape)
- `/specs/architecture.md` §10 failure modes
- `/specs/phase-4/architecture.md` §1 generation flow, §2 `AI.GenerationWorker`, §9 telemetry/events

## Acceptance criteria

- [x] AC1: `AI.GenerationWorker` loads required context, invokes adapter + validator chain, and writes `Draft.:complete_generation`/`:fail_generation` via worker context. — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_test.exs`
- [x] AC2: Worker handles adapter timeout/error classes deterministically without mutating send-stage records (`Action`/`Compensation`). — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_failure_test.exs`
- [x] AC3: Worker path emits expected telemetry events/metadata (model, token/caching counters, validator outcome signals). — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_telemetry_test.exs`
- [x] AC4: Enqueue semantics are idempotent for same draft generation request shape (no duplicate terminal state corruption). — Verify: `mix test test/ashy_walnut_desk/ai/jobs/generation_worker_idempotency_test.exs`

## Files to create

```
lib/ashy_walnut_desk/ai/jobs/generation_worker.ex                        — oban orchestration worker

test/ashy_walnut_desk/ai/jobs/generation_worker_test.exs
test/ashy_walnut_desk/ai/jobs/generation_worker_failure_test.exs
test/ashy_walnut_desk/ai/jobs/generation_worker_telemetry_test.exs
test/ashy_walnut_desk/ai/jobs/generation_worker_idempotency_test.exs
```

## Files to modify

```
config/config.exs                                                        — oban queue + telemetry wiring for AI generation
lib/ashy_walnut_desk/interaction/draft.ex                                — enqueue hook integration (if deferred from 4.5)
```

## Implementation notes

Reuse established Phase 3 worker posture: worker owns internal transitions; UI never transitions to completed/failed directly.

## Safety review

- Sensitive records touched? yes — prompt/response/validator artifacts
- AI output to end user possible? yes — persists into draft review
- Guardrails applied? validator chain enforced server-side
- Audit trail covered? yes — completion/failure events through chain actions

## Out of scope (will NOT do in this story)

- LiveView generation panel/UX: deferred to story 4.7
- Preflight/deployer docs/integration gate: deferred to story 4.8

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/ai/jobs/generation_worker_test.exs
mix test test/ashy_walnut_desk/ai/jobs/generation_worker_failure_test.exs
mix test test/ashy_walnut_desk/ai/jobs/generation_worker_telemetry_test.exs
mix test test/ashy_walnut_desk/ai/jobs/generation_worker_idempotency_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Added `drafts.persona_id` as nullable FK and `Draft.belongs_to :persona` (manual drafts remain persona-less), then wired model stamping from persona/default at `Draft.:generate`.
- Enforced disclosure append server-side in `Draft.:complete_generation` via a resource change so operator edits cannot bypass immutable-at-generation disclosure stamping.
- `AI.GenerationWorker` retries only transient classes (`:transient`, `:rate_limited`, `:timeout`), terminal-fails permanent classes (`:permanent`, `:content_blocked`, validator failure), and no-ops idempotently if draft is no longer `:generating`.
- Spec drift noticed:
- `specs/phase-4/architecture.md` had an internal contradiction: §3.2 required `Draft.:generate accept([:inbox_id, :persona_id])` while §10.1 claimed no new columns on `drafts`; implementation follows §3.2 and adds `drafts.persona_id`.
- Story 4.5 note said enqueue/disclosure were deferred; this story implements both (`EnqueueGenerationWorker` on `:generate`, disclosure append on `:complete_generation`) to match Phase 4 architecture runtime behavior.
- Gotchas to add to AGENTS.md §10:
- None discovered beyond already-documented Oban test/manual and admin uniqueness gotchas.
