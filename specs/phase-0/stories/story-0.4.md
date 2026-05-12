# Story 0.4: Install AshPaperTrail at app level

**Phase**: 0
**Estimate**: 1h
**Depends on**: 0.1
**Status**: ready

---

## Goal

Configure AshPaperTrail at the app level so subsequent stories can opt resources in with one line. No Phase 0 resource opts in here.

## Context

Phase 0 requirements §2 require "AshPaperTrail enabled (no resources to audit yet, just config)". Per architecture §3 + §9 + §10, the per-resource opt-in decision for `User` is made during the auth-install story (0.5), not here. This story is the framework-capability deliverable: install + config + any support tables.

## Reference specs

- `/AGENTS.md` §6 (sensitive-record changes audited via AshPaperTrail)
- `/AGENTS.md` §10 (gotcha: AshPaperTrail must be enabled BEFORE inserting data)
- `/specs/phase-0/architecture.md` §9 (audit), §10 (safety review summary)

## Acceptance criteria

- [ ] AC1: `mix deps` resolves `:ash_paper_trail` (already declared in 0.1's `mix.exs`). Verify: `mix deps | grep ash_paper_trail` shows it as `ok`.
- [ ] AC2: AshPaperTrail configuration block in `config/config.exs` references the project Repo and follows AshPaperTrail's documented setup. Verify: `grep -q AshPaperTrail config/config.exs`.
- [ ] AC3: Any AshPaperTrail support tables generated and migrated cleanly. Verify: `mix ash_postgres.generate_migrations --name install_paper_trail` followed by `mix ecto.migrate` exits 0.
- [ ] AC4: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

```
priv/repo/migrations/<ts>_install_paper_trail.exs   — generated if support tables are required
```

## Files to modify

```
config/config.exs   — AshPaperTrail config block
```

## Implementation notes

- Order matters: per AGENTS.md §10, AshPaperTrail must be enabled before any audited resource creates rows. That is why this story precedes 0.5 (User resource).
- No resource opts in during this story; the framework hook is the deliverable. Per-resource opt-in is decided in 0.5.
- If AshPaperTrail does not require any support tables for the default setup, skip the migration file and document that in "Notes during implementation".

## Safety review

N/A at the resource level — framework-capability install only. No sensitive data flows yet.

## Out of scope

- Per-resource opt-in (decided in 0.5).
- Custom version-store backend beyond AshPaperTrail defaults.
- Retention/expiry policy for version history (Phase 5 meta-ops concern).

## Verification

```bash
just verify
grep -q AshPaperTrail config/config.exs
mix ecto.migrations | grep paper_trail
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
