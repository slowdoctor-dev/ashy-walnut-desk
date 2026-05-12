# Story 0.5: AshAuthentication install + Accounts.User + Accounts.Token

**Phase**: 0
**Estimate**: 2.5h
**Depends on**: 0.1, 0.2
**Status**: done

---

## Goal

Install AshAuthentication with the magic-link strategy, create the `AshyWalnutDesk.Accounts` Ash domain, and create the `User` and `Token` resources matching architecture §3.

## Context

Largest story in Phase 0 because the resource pair, auth strategy, and policies all land together. Splitting them would produce an unrunnable intermediate (User without auth, or auth without User). Per architecture §3, Phase 0 introduces these two resources and no others. The story deliberately exceeds the ≤5-files heuristic because the work is functionally cohesive — splitting on a count rule alone would create artificial coupling.

## Reference specs

- `/specs/phase-0/architecture.md` §3 (attributes, actions, policies, sensitive markers)
- `/specs/phase-0/architecture.md` §9 (security — hash salt from runtime env)
- `/AGENTS.md` §6 (intent-verb actions, policies required, sensitive-record audit mandatory)
- `/specs/phase-0/architecture.md` §9 (Audit) and §10 (Audit trail coverage) — User audit is mandatory in Phase 0

## Acceptance criteria

- [x] AC1: `mix ash_authentication.install --auth-strategy magic_link` succeeds; files are reorganized (or generated directly) to match the architecture's `lib/ashy_walnut_desk/accounts/` layout. Verify: `ls lib/ashy_walnut_desk/accounts.ex lib/ashy_walnut_desk/accounts/user.ex lib/ashy_walnut_desk/accounts/token.ex` all exist.
- [x] AC2: `User` has attributes `email` (sensitive? true), `email_hash` (SHA-256 of normalized email, salted by `IDENTIFIER_HASH_SALT` from runtime env), `role` (`:admin | :operator`), `confirmed_at`, `last_signed_in_at`. Verify: `mix test test/ashy_walnut_desk/accounts/user_test.exs` includes attribute introspection and a hash-determinism test.
- [x] AC3: `User` policies match architecture §3 (unauthenticated may request/complete magic-link; `:self` reads own; `:admin` reads all and assigns roles; `:operator` reads own; system performs auth-flow updates). Verify: `mix test test/ashy_walnut_desk/accounts/user_test.exs` includes one policy assertion per actor row.
- [x] AC4: `Token` resource uses `AshAuthentication.TokenResource` defaults; token-material is sensitive; tokens are not retrievable via any UI-facing read. Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs` includes a sensitive-introspection check and a "Public actor cannot read tokens" test.
- [x] AC5: `User` opts in to AshPaperTrail per AGENTS.md §6 ("ALL sensitive-record changes audited via AshPaperTrail"). The resource declares `extensions: [..., AshPaperTrail.Resource, ...]` AND has a `paper_trail do ... end` block in `lib/ashy_walnut_desk/accounts/user.ex`. A unit test in `user_test.exs` performs an `update` action on a fixture user and asserts a new version row exists. Verify: `grep -q 'AshPaperTrail.Resource' lib/ashy_walnut_desk/accounts/user.ex && mix test test/ashy_walnut_desk/accounts/user_test.exs` passes the audit-version assertion. If the AshAuthentication-generated `User` shape resists a clean opt-in, the story is **blocked** pending an ADR amendment; do not silently defer.

## Files to create

```
lib/ashy_walnut_desk/accounts.ex                       — Ash domain
lib/ashy_walnut_desk/accounts/user.ex                  — User resource
lib/ashy_walnut_desk/accounts/token.ex                 — Token resource
test/ashy_walnut_desk/accounts/user_test.exs           — attribute, hash, policy tests
test/ashy_walnut_desk/accounts/token_test.exs          — sensitive + policy tests
```

## Files to modify

```
config/config.exs    — register Accounts domain with ash_domains
config/runtime.exs   — read IDENTIFIER_HASH_SALT and feed to the hashing logic
```

## Implementation notes

- Per architecture §3 implementation note: keep AshAuthentication's generated internals; expose the architecture's intent through documentation and tests. Never bypass Ash actions with direct `Repo` calls.
- `email_hash` may be implemented as an Ash `calculate` derived from `email`, or as a stored attribute populated via a `before_action` change. Either is acceptable; pick the one that integrates cleanly with the AshAuthentication-generated User shape.
- `IDENTIFIER_HASH_SALT` is already provisioned in `.env` (Day 1 setup).
- First-user-admin logic is deferred to Story 0.6.

## Safety review

- Sensitive records touched? **Yes** — `User.email`, `User.email_hash`, `Token.token`. All marked sensitive.
- AI output to end user possible? **No** — no AI in Phase 0.
- Guardrails applied? Ash policies per §3; raw token never logged; email normalized then hashed.
- Audit trail covered? Yes — `User` opts in to AshPaperTrail in AC5 (mandatory, not deferrable). Framework-level install came in 0.4.

## Out of scope

- First-user admin assignment → Story 0.6.
- Phoenix UI for sign-in → Story 0.7.
- WelcomeLive integration → Story 0.8.
- Token cleanup via Oban (deferred; AshAuthentication defaults are sufficient for Phase 0).

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/accounts/
```

## Notes during implementation

- Decisions made:
  - Hand-authored the Accounts domain + User + Token resources (AC1's
    "or generated directly" clause) because `mix ash_authentication.install`
    and `mix igniter.install ash_authentication` both hung on interactive
    prompts in the non-tty sandbox, including with `--yes` and a pinned
    version (`ash_authentication@4.13.7`).
  - Took the separate-setup-migration path for citext (AC1 prep): a
    hand-authored `20260512143957_enable_citext.exs` runs one second
    before the auto-generated `20260512143958_add_accounts_auth.exs`, so
    `mix ash_postgres.generate_migrations` can regenerate the resource
    migration without losing the extension setup. Mirrors story 0.2's
    `enable_extensions` pattern.
  - Read policy on User started as `authorize_if always()` (would have
    leaked every record). Tightened to admin OR self via
    `actor_attribute_equals(:role, :admin) || expr(id == ^actor(:id))`.
  - Test assertions use real action calls + tuple match (`assert {:ok, _}
    = Ash.update(...)` / `assert {:error, _} = ...`) rather than
    `Ash.can` introspection — more robust against changes to the policy
    DSL's return shape.
- Spec drift noticed:
  - `igniter ~> 0.6` (`only: [:dev, :test], runtime: false`) was added
    to mix.exs in this story because `mix ash_authentication.install`
    requires it; story 0.1's deps list didn't include it. Not a blocker
    — igniter is a generator-only dep — but worth noting for future
    spec hygiene.
  - Repo upgraded from `use Ecto.Repo` to `use AshPostgres.Repo` with
    `installed_extensions: ["pgvector", "pg_trgm", "citext"]`. Crosses
    story-0.1's boundary (Repo lived there) but is a hard prerequisite
    of AshPostgres + this story's resources. Reasonable necessity.
- Gotchas to add to AGENTS.md §10:
  - `mix ash_authentication.install` / `mix igniter.install` hang in
    non-tty environments even with `--yes`; if running in a sandboxed
    pipeline, hand-author resources from the AshAuthentication module
    docs instead of fighting the generator.
  - The auto-generated AshPostgres migration assumes citext (and any
    other extension referenced by a resource) is already enabled —
    extension setup belongs in a separate timestamp-earlier migration.
- AshPaperTrail-on-User decision (AC5):
  - Cleanly opted in. `User` declares
    `extensions: [AshAuthentication, AshPaperTrail.Resource]` and a
    `paper_trail do` block; `User.Version` is registered in the Accounts
    domain. The `:assign_role` test in `user_test.exs` performs an
    `update` and asserts `versions != []` against `User.Version` filtered
    by `version_source_id`. No ADR amendment was needed — the generator
    didn't resist the opt-in because we didn't use the generator.
