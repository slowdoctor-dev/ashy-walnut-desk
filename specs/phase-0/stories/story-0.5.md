# Story 0.5: AshAuthentication install + Accounts.User + Accounts.Token

**Phase**: 0
**Estimate**: 2.5h
**Depends on**: 0.1, 0.2
**Status**: ready

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

- [ ] AC1: `mix ash_authentication.install --auth-strategy magic_link` succeeds; files are reorganized (or generated directly) to match the architecture's `lib/ashy_walnut_desk/accounts/` layout. Verify: `ls lib/ashy_walnut_desk/accounts.ex lib/ashy_walnut_desk/accounts/user.ex lib/ashy_walnut_desk/accounts/token.ex` all exist.
- [ ] AC2: `User` has attributes `email` (sensitive? true), `email_hash` (SHA-256 of normalized email, salted by `IDENTIFIER_HASH_SALT` from runtime env), `role` (`:admin | :operator`), `confirmed_at`, `last_signed_in_at`. Verify: `mix test test/ashy_walnut_desk/accounts/user_test.exs` includes attribute introspection and a hash-determinism test.
- [ ] AC3: `User` policies match architecture §3 (unauthenticated may request/complete magic-link; `:self` reads own; `:admin` reads all and assigns roles; `:operator` reads own; system performs auth-flow updates). Verify: `mix test test/ashy_walnut_desk/accounts/user_test.exs` includes one policy assertion per actor row.
- [ ] AC4: `Token` resource uses `AshAuthentication.TokenResource` defaults; token-material is sensitive; tokens are not retrievable via any UI-facing read. Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs` includes a sensitive-introspection check and a "Public actor cannot read tokens" test.
- [ ] AC5: `User` opts in to AshPaperTrail per AGENTS.md §6 ("ALL sensitive-record changes audited via AshPaperTrail"). The resource declares `extensions: [..., AshPaperTrail.Resource, ...]` AND has a `paper_trail do ... end` block in `lib/ashy_walnut_desk/accounts/user.ex`. A unit test in `user_test.exs` performs an `update` action on a fixture user and asserts a new version row exists. Verify: `grep -q 'AshPaperTrail.Resource' lib/ashy_walnut_desk/accounts/user.ex && mix test test/ashy_walnut_desk/accounts/user_test.exs` passes the audit-version assertion. If the AshAuthentication-generated `User` shape resists a clean opt-in, the story is **blocked** pending an ADR amendment; do not silently defer.

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
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
- AshPaperTrail-on-User decision (AC5):
