# Story 0.6: First-user-admin Ash change + race-safe constraint

**Phase**: 0
**Estimate**: 1.5h
**Depends on**: 0.5
**Status**: done

---

## Goal

Implement `AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdmin` so the first successful registration receives `:admin` and all subsequent registrations receive `:operator`. Add a DB-level partial-unique index that admits at most one `:admin` row so a concurrent race resolves correctly per architecture §8.2.

## Context

Story 0.5 left `User` with a `role` attribute but no first-user logic and no DB-level guard against concurrent first signups both being assigned `:admin`. Architecture §6.1 + §8.2 require both an application-level intent (the change) and a DB-level guarantee (the partial index) — neither alone is sufficient.

## Reference specs

- `/specs/phase-0/architecture.md` §3 (`register_with_magic_link` action)
- `/specs/phase-0/architecture.md` §6.1 (first-user-check inside the signup flow)
- `/specs/phase-0/architecture.md` §8.2 (race condition + partial-unique index)

## Acceptance criteria

- [x] AC1: `lib/ashy_walnut_desk/accounts/changes/assign_first_user_admin.ex` is an Ash change wired into `User`'s `register_with_magic_link` action; sets `role: :admin` iff no other User row exists, else `:operator`. Verify: `mix test test/ashy_walnut_desk/accounts/changes/assign_first_user_admin_test.exs` covers both branches.
- [x] AC2: A partial-unique index `users_one_admin_idx` on `users(role) WHERE role = 'admin'` exists. Verify: `mix ecto.migrate` succeeds and `docker compose exec db psql -U postgres -d ashy_walnut_desk_dev -c "\d users"` shows the partial index.
- [x] AC3: Race test — two concurrent `register_with_magic_link` Tasks against an empty users table yield exactly one `:admin`; the loser is created as `:operator` (DB rejection caught and recovered cleanly). Verify: `mix test test/ashy_walnut_desk/accounts/first_user_race_test.exs`.
- [x] AC4: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

```
lib/ashy_walnut_desk/accounts/changes/assign_first_user_admin.ex   — Ash change
test/ashy_walnut_desk/accounts/changes/assign_first_user_admin_test.exs   — unit tests
test/ashy_walnut_desk/accounts/first_user_race_test.exs            — concurrent-Task race test
priv/repo/migrations/<ts>_add_users_one_admin_index.exs            — generated via ash_postgres.generate_migrations
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/user.ex   — wire the change into register_with_magic_link
```

## Implementation notes

- The partial-unique index is the **actual race guard**; the Ash change is the application-level intent that succeeds in the no-race case. Per architecture §8.2, both layers are required.
- The race test uses `Task.async_stream` or equivalent. The losing Task's transaction will be rejected by the unique-index violation — the action must catch that and retry as `:operator`. Document the retry path in the change module.
- Update the snapshot in `priv/repo/resource_snapshots/` if the index addition requires it (AshPostgres-generated migration handles this automatically).

## Safety review

- Sensitive records touched? **Yes** — `User` (continues from 0.5).
- AI output to end user possible? **No**.
- Guardrails applied? Policies from 0.5 still apply.
- Audit trail covered? Per the AshPaperTrail-on-User decision recorded in 0.5.

## Out of scope

- Manual admin-promotion UI — no LiveView for admin actions in Phase 0; `assign_role` is action-only.
- Admin demotion safety (preventing the last admin from being demoted) — deferred until there is a multi-admin workflow (Phase 1+).

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/accounts/changes/
mix test test/ashy_walnut_desk/accounts/first_user_race_test.exs
```

## Notes during implementation

- Decisions made:
- Wired `AssignFirstUserAdmin` into `:sign_in_with_magic_link` (not `:register`) because AshAuthentication magic-link registration with `registration_enabled? true` creates users through `:sign_in_with_magic_link` upsert. This is the real signup path.
- Spec drift noticed:
- Story/architecture references `register_with_magic_link`, but the implemented 0.5 action set is `:register` (fixture upsert helper) and `:sign_in_with_magic_link` (auth-generated signup/sign-in action). 0.6 implements the invariant on `:sign_in_with_magic_link` and keeps `:register` available for tests/fixtures.
- Gotchas to add to AGENTS.md §10:
