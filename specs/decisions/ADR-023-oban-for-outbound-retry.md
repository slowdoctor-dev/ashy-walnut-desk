# ADR-023: Oban for outbound retry envelope

**Status**: Accepted
**Date**: 2026-05-18
**Deciders**: solo maintainer

---

## Context

Phase 2's `Action.:execute` is a single DB transaction with an
inline adapter call (`Adapters.Stub.send_outbound/2`). The stub
returns instantly without network I/O, so no retry is needed.

Phase 3 introduces real network I/O through Twilio. Network calls
fail transiently (provider 5xx, rate limits, transient DNS,
operator-network-flap, etc.). Phase 3 requirements §2 AC #10:

> Provider/network failures follow explicit retry policy and
> terminal-failure policy (test-covered), with no autonomous
> bypass of human approval rules.

The framework needs a retry mechanism that:

1. Doesn't block the operator's LiveView request.
2. Survives BEAM restarts.
3. Doesn't double-send on retry (composes with the idempotency-
   key contract in §12 Q4).
4. Surfaces terminal failures back to the operator UI.
5. Doesn't introduce a new dependency category if avoidable.

## Options considered

### Option 1: Inline retry in `Action.:execute`

`Action.:execute` runs in the LV process. Loop with `Process.sleep`
backoff inside the action body, retry on `{:error, :transient}`,
break out on `{:error, :permanent}` or success.

- **Pros**: zero new infrastructure; chain stays in one transaction.
- **Cons**: blocks the LV process for the entire retry window (up
  to hours); loses retries if the LV process dies; the DB
  transaction can't span network retries (DB connection times out;
  long transactions hold locks); the operator's countdown UI
  freezes.

Verdict: incompatible with the LV/Phoenix process model.

### Option 2: New Elixir-supervised retry process

Spawn a `Task.Supervisor` per Action with retry-with-backoff
logic. Persist state to a new ETS table or DB row for crash
recovery.

- **Pros**: pure Elixir; no new deps.
- **Cons**: reinvents a job queue badly — we'd need our own
  scheduling, crash recovery, retry-budget tracking, dead-letter
  handling. Each of these is a small bug magnet.

Verdict: NIH reimplementation of Oban.

### Option 3: Oban (already in deps)

Oban already ships in the project (Phase 0 added it; `Token.:expunge_expired`
uses an `AshOban.Trigger`). Phase 3 adds one new queue
(`:outbound`) and one new worker (`Jobs.OutboundSend`).

- **Pros**: battle-tested retry / backoff / dead-letter behaviour;
  durable across BEAM restarts (jobs are Postgres rows); observable
  via the existing Oban Web dashboard or `iex` queries; no new
  dependency; pattern matches Phase 0's existing usage.
- **Cons**: jobs run in worker processes outside the LV context,
  so the worker needs to thread actor / context properly for the
  internal-only chain transitions (Inbox.:mark_executed,
  Message.:record_message). The worker must use the existing
  `from_action_execute` context flag pattern (per Phase 2 PR #37).

Verdict: clean fit. The minor cost is well-covered by the
existing context-flag pattern.

### Option 4: External job queue (Redis-backed Sidekiq-style)

Add a new dependency for job processing.

- **Pros**: well-known operator-friendly tooling.
- **Cons**: ADR-003 commits the project to a single Postgres
  instance; adding Redis violates that. Oban is Postgres-backed
  and already there.

Verdict: violates ADR-003.

## Decision

We chose **Option 3: Oban**.

Reasoning:

- Already in deps; pattern already used by `Token.:expunge_expired`.
- Postgres-backed (ADR-003 compliant).
- Durable retry budget survives BEAM restart.
- Per-attempt timeout + backoff are configurable via worker
  `meta`; Phase 3's defaults (30s → 2m → 10m → 30m → 2h, 5
  attempts) are documented in `specs/phase-3/architecture.md §12 Q3`.

## Consequences

### Positive

- `Action.:execute` becomes a "schedule and return" operation,
  freeing the LV process immediately. Operator UI shows
  `:pending → :scheduled → :executed | :failed` transitions via
  PubSub.
- Crash recovery is automatic: a BEAM restart mid-send finds the
  job still queued and re-runs it; the idempotency key prevents
  Twilio double-send (Q4 decision).
- Dead-letter behaviour is built in: after 5 attempts, Oban marks
  the job `:discarded` and our `Jobs.OutboundSend.handle_terminal_failure/2`
  callback transitions `Action.status: :failed` + writes the
  `:action_executed` audit event with `outcome: :failed`.

### Negative / accepted trade-offs

- Oban workers run outside the LV's actor context. The worker must
  reload the Action + Channel + Draft and explicitly pass
  `context: %{from_action_execute: true}` for the internal-only
  transitions (Inbox.:mark_executed, Message.:record_message).
  This follows the Phase 2 PR #37 pattern; no new mechanism.
- `Action.:execute`'s chain semantics split: the validation +
  audit-event writes happen at schedule time (LV process); the
  adapter call + outcome stamping happen at job time (worker
  process). Two transactions; documented in `architecture.md §6.1`.
- A worker crash mid-send (BEAM termination after Twilio accepted
  but before we wrote `Action.status: :executed`) is recovered on
  worker restart via the idempotency key — Twilio replies `409
  Conflict` with the original payload, which we treat as success.

### Follow-up actions

- [x] `lib/ashy_walnut_desk/interaction/jobs/outbound_send.ex` —
      Oban worker
- [x] `config/runtime.exs` Oban queues block adds
      `[outbound: 5, …]` (concurrency 5 = Twilio's default
      per-number rate limit)
- [x] `EnqueueOutboundSend` change module on `Action.:execute`
      that calls `Oban.insert(Jobs.OutboundSend, …)` with
      `unique: [period: 60]` keyed on `action_id`
- [x] Compensation invocation reuses the same worker via a
      `kind: :compensation, compensation_id: <uuid>` job arg
      branch
- [x] Property test on idempotency: every `(action_id,
      idempotency_key)` pair maps to ≤1 outbound Twilio request,
      even under retry

## References

- Related ADRs: ADR-003 (Single Postgres + pgvector), ADR-009
  (PubSub + Oban for messaging), ADR-016 (Four-stage record
  chain), ADR-022 (Twilio as first real adapter)
- External: https://hexdocs.pm/oban/Oban.html#module-job-retries
- Phase 3 requirements: `specs/phase-3/requirements.md` AC #10, AC #15
- Phase 3 architecture: `specs/phase-3/architecture.md §6.1, §12 Q3`
