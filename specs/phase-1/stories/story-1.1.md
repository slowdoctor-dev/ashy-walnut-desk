# Story 1.1: Identity domain bootstrap + viewer role

**Phase**: 1
**Estimate**: 2h
**Depends on**: —
**Status**: done

---

## Goal

Create the minimal Phase 1 foundation by introducing the `AshyWalnutDesk.Identity` domain and adding the `:viewer` role to Accounts so subsequent Identity stories can enforce read-only access.

## Context

This is the Phase 1 hello-world story required by BMAD PM guidance. It establishes the domain entry point and role baseline used by every later story.

## Reference specs

- `/AGENTS.md` §6 (Ash actions/policies standards)
- `/specs/phase-1/requirements.md` §2 (AC11: viewer role)
- `/specs/phase-1/architecture.md` §2 (Affected modules, Identity domain + User role enum)

## Acceptance criteria

- [x] AC1: `lib/ashy_walnut_desk/identity.ex` exists and defines the new Identity Ash domain with no resources yet, compiling cleanly. — Verify: `mix compile`
- [x] AC2: `Accounts.User` role constraints include `:viewer` alongside `:admin` and `:operator`. — Verify: `mix test test/ashy_walnut_desk/accounts/user_test.exs`
- [x] AC3: Existing auth and policy tests still pass after role enum extension. — Verify: `mix test test/ashy_walnut_desk/accounts`

## Files to create

```
lib/ashy_walnut_desk/identity.ex   — Identity Ash.Domain bootstrap
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/user.ex   — extend role enum to include :viewer
test/ashy_walnut_desk/accounts/user_test.exs   — role enum regression assertion
```

## Implementation notes

Keep this story intentionally small: domain module + role enum only. Do not add Identity resources yet.

## Safety review

- Sensitive records touched? No new customer records yet.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? N/A in this bootstrap story.

## Out of scope (will NOT do in this story)

- Identity/Event/Appointment/Note resources: deferred to 1.2–1.5
- LiveView identity pages/timeline: deferred to 1.6
- TO-3 token expunge: deferred to 1.8

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/accounts/user_test.exs
```

## Notes during implementation

- Decisions made:
  - Registered `AshyWalnutDesk.Identity` in `config :ashy_walnut_desk, ash_domains: […]` so the new domain is discoverable by Ash tooling (mirrors how `Accounts` is wired); the domain compiles with an empty `resources do … end` block per AC1.
- Spec drift noticed:
  - `specs/phase-1/architecture.md §2` anticipates a generated migration
    `*_alter_users_role_add_viewer.exs` for the role enum extension.
    The current `users.role` column is stored as Postgres `text`
    (confirmed in `priv/resource_snapshots/repo/users/20260512162015.json`,
    `"type": "text"`), and Ash's `one_of` constraint is enforced in
    Elixir, not as a CHECK/ENUM at the DB layer. So adding `:viewer`
    is a constraint-only change with no DB migration in Story 1.1. The
    architecture note is forward-looking (would apply if the column
    were ever promoted to a Postgres ENUM) but doesn't require action
    now. Leaving the architecture text as-is since it's accurate as
    an "if we ever migrate to ENUM" reminder rather than a Phase 1
    deliverable.
- Gotchas to add to AGENTS.md §10:
  - None new; the text-vs-ENUM nuance is captured in the spec-drift
    note above and is too specific to this Phase 1 column to warrant
    a global Gotchas entry.
