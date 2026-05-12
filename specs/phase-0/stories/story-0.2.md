# Story 0.2: Enable PostgreSQL extensions (pgvector + pg_trgm)

**Phase**: 0
**Estimate**: 1h
**Depends on**: 0.1
**Status**: done

---

## Goal

Add a setup migration that enables the `vector` and `pg_trgm` extensions before any Ash resource migration runs.

## Context

Phase 0 requirements §2 require both extensions to be enabled. Architecture §7 calls for an extension-enable migration that precedes resource migrations. Phase 0 does not *use* these extensions yet (RAG → Phase 5, fuzzy search later); enabling them now keeps the install off the critical path of later phases at the cost of one cheap migration.

## Reference specs

- `/AGENTS.md` §5 (use `mix ash_postgres.generate_migrations`, not `mix ecto.gen.migration`)
- `/specs/phase-0/architecture.md` §7 (migration plan, order)
- `/specs/phase-0/requirements.md` §2 (extensions AC)

## Acceptance criteria

- [x] AC1: A migration `priv/repo/migrations/<ts>_enable_extensions.exs` runs `CREATE EXTENSION IF NOT EXISTS vector` and `CREATE EXTENSION IF NOT EXISTS pg_trgm`. Verify: `mix ecto.migrate` succeeds, then `docker compose exec db psql -U postgres -d ashy_walnut_desk_dev -tAc "SELECT extname FROM pg_extension WHERE extname IN ('vector','pg_trgm') ORDER BY extname;"` outputs exactly the two lines `pg_trgm` and `vector`.
- [x] AC2: Migration `down/0` is a documented no-op for extension drops. Verify: `mix ecto.rollback --step 1` exits 0 and the migration file contains a `# down: intentional no-op` comment.
- [x] AC3: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

```
priv/repo/migrations/<ts>_enable_extensions.exs   — hand-written extension setup
```

## Files to modify

— (none)

## Implementation notes

- Hand-write this migration; it is a setup migration, not generated from Ash resources.
- Use `execute("CREATE EXTENSION IF NOT EXISTS vector")` and `execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")` inside `up/0`.
- Inside `down/0`: comment explaining why dropping is unsafe on a shared cluster, then `:ok`.
- Migration must be timestamped earlier than any resource migration so the extensions exist when resource migrations later reference them.

## Safety review

N/A — infrastructure migration, no sensitive data, no resource changes.

## Out of scope

- Actually using pgvector (Phase 5).
- Actually using pg_trgm (later phases).
- Any other extension — none required by Phase 0.

## Verification

```bash
just verify
docker compose exec db psql -U postgres -d ashy_walnut_desk_dev \
  -c "SELECT extname FROM pg_extension WHERE extname IN ('vector','pg_trgm');"
# expect: 2 rows (vector, pg_trgm)
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Added a hand-written setup migration `20260512150000_enable_extensions.exs` so extension enablement is explicit and independent of future resource generation.
- Kept `down/0` as an intentional no-op to avoid unsafe extension drops in shared clusters.
- Spec drift noticed:
- None.
- Gotchas to add to AGENTS.md §10:
- None.
