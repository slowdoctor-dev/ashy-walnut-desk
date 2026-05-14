# Story 1.8: TO-3 token expunge schedule via AshOban

**Phase**: 1
**Estimate**: 1h
**Depends on**: 1.1
**Status**: done

---

## Goal

Resolve TO-3 by scheduling recurring expired-token expunge and validating expired rows are removed while valid rows remain.

## Context

TO-3 was explicitly deferred from Phase 0 and is in-scope for Phase 1 but largely independent of Identity-resource implementation.

## Reference specs

- `/AGENTS.md` §10 gotchas (TO-3 context)
- `/specs/phase-1/requirements.md` §2 (AC14)
- `/specs/phase-1/architecture.md` §6.3 and §11 (Background/AshOban testing)
- `/specs/security/known-trade-offs.md` (TO-3)

## Acceptance criteria

- [x] AC1: `Accounts.Token` has recurring expunge trigger configuration that calls `:expunge_expired`. — Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs`
- [x] AC2: Regression test asserts expired token rows are deleted and unexpired rows are retained after trigger/action run. — Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs`
- [x] AC3: No regressions in authentication token behavior under existing auth tests. — Verify: `mix test test/ashy_walnut_desk/accounts`

## Files to create

```
(none expected)
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/token.ex   — add AshOban trigger config
test/ashy_walnut_desk/accounts/token_test.exs   — expunge schedule regression tests
config/runtime.exs   — only if scheduler config required by chosen trigger pattern
```

## Implementation notes

Prefer resource-local trigger configuration per architecture recommendation.

## Safety review

- Sensitive records touched? Yes — authentication token lifecycle records.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? Token hygiene story; audit not primary path.

## Out of scope (will NOT do in this story)

- Identity-axis resource behavior: covered in 1.2–1.7
- Deployment-specific retention policy windows: deferred to deployer repo

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/accounts/token_test.exs
```

## Notes during implementation

- Decisions made:
  - Trigger named `:expunge_tokens` (per architecture §11), action name `:expunge_expired` (the existing TokenResource destroy action), keeping the two distinct.
  - Resource-local trigger config in `Token` per architecture §12 Q1 recommendation; no `Accounts.OperationalTasks` shim added.
  - Schedule: `"0 3 * * *"` (daily 03:00 UTC) per architecture §6.3.
  - Queue: `:tokens` (explicit, added to `runtime.exs`); short and predictable, vs the AshOban default `:token_expunge_tokens`.
  - Added `pagination keyset?: true, required?: false` to the existing `:expired` read action (AshOban requires keyset pagination on the trigger's `read_action`). No production callers, so widening the action surface is safe.
  - Set `worker_module_name` / `scheduler_module_name` explicitly so trigger renames don't strand cron jobs (per AshOban guidance).
  - Bypass `AshOban.Checks.AshObanInteraction` in `Token` policies (alongside the existing `AshAuthenticationInteraction` bypass) so the scheduler/worker can read and destroy without a real actor.
  - Wired `AshOban.config/2` around the Oban supervisor in `application.ex`, and added `Oban.Plugins.Cron` (with empty crontab) to `config/config.exs` so AshOban can populate cron entries at boot.
  - Added `config :ashy_walnut_desk, Oban, testing: :manual` to `config/test.exs` so `AshOban.Test.schedule_and_run_triggers/2` can drive triggers synchronously against the sandbox connection. This is the standard Oban testing posture — without it `drain_queues?: true` raises.
- Spec drift noticed:
  - Architecture §6.3 names the trigger `:expunge_tokens` and shows `Ash.bulk_destroy(Token, :expunge_expired, %{}, authorize?: false)`. Implemented as a per-record AshOban trigger (the AshOban primitive); the destroy action is per-row but the trigger's `where` filter and the action's existing `change(filter(...))` together preserve the same effect (expired rows only). Token volume in prod is small enough that per-row jobs are fine; no need for Oban Pro chunking.
- Gotchas to add to AGENTS.md §10:
  - AshOban triggers require `pagination keyset?: true, …` on the read_action they stream; forgetting it raises a `Spark.Error.DslError`.
  - `AshOban.Test.schedule_and_run_triggers/2` requires `config :my_app, Oban, testing: :manual` (or Oban Pro) in test env; otherwise `drain_queues?: true` raises. With `:manual`, `Oban.config().queues` is `[]` at runtime — assertions about configured queues must read `Application.get_env(...)` instead of `Oban.config/0`.
