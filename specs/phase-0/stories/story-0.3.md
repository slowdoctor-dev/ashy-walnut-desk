# Story 0.3: Configure Oban with default/messages/ai/reindex queues

**Phase**: 0
**Estimate**: 1.5h
**Depends on**: 0.1
**Status**: ready

---

## Goal

Add Oban to the supervision tree with four queues — `default`, `messages`, `ai`, `reindex` — and run the Oban migration. No workers are introduced in Phase 0.

## Context

Phase 0 requirements §2 require Oban with these four queues. Architecture §1 (Background Runtime) confirms the layout. Only `default` will see jobs in Phase 0 (none yet wired); the other three exist now so later phases plug workers in without revisiting Oban config.

## Reference specs

- `/specs/phase-0/architecture.md` §1, §2 (Application/runtime)
- `/AGENTS.md` §10 (gotcha: Oban queue config in `config/runtime.exs`)

## Acceptance criteria

- [ ] AC1: Oban migration `priv/repo/migrations/<ts>_oban_setup.exs` runs `Oban.Migration.up/0`. Verify: `mix ecto.migrate` succeeds and `docker compose exec db psql -U postgres -d ashy_walnut_desk_dev -c "\d oban_jobs"` returns the table.
- [ ] AC2: `AshyWalnutDesk.Application` starts `Oban` as a supervised child. Verify: in `iex -S mix phx.server`, `Process.whereis(Oban)` returns a pid.
- [ ] AC3: Runtime queue config in `config/runtime.exs` declares all four queues with sensible defaults. Verify: `iex` → `Oban.config().queues` returns a keyword list containing `default`, `messages`, `ai`, `reindex`.
- [ ] AC4: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

```
priv/repo/migrations/<ts>_oban_setup.exs   — Oban schema migration (Oban.Migration.up/0)
```

## Files to modify

```
lib/ashy_walnut_desk/application.ex   — add {Oban, ...} to supervision tree
config/config.exs                     — base Oban config (repo, queues placeholder)
config/runtime.exs                    — runtime queue concurrency settings
```

## Implementation notes

- Default concurrencies: `default: 10, messages: 10, ai: 5, reindex: 5`. Tune later if a queue saturates.
- Phase 0 does not introduce any worker module; queues exist empty by design.
- `ash_oban` integration (linking Ash actions to Oban) is deferred — no Phase 0 resource has an Oban-backed action.

## Safety review

N/A — queue scaffolding, no sensitive data, no resource changes.

## Out of scope

- Worker modules (Phase 2+).
- `ash_oban` resource integration.
- Queue-saturation alerting (Phase 5 meta-ops).

## Verification

```bash
just verify
iex -S mix phx.server
> Process.whereis(Oban)
> Oban.config().queues
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
