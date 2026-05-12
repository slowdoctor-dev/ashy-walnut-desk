# Story 0.7: AshAuthentication Phoenix UI mounting

**Phase**: 0
**Estimate**: 1.5h
**Depends on**: 0.5
**Status**: ready

---

## Goal

Mount the AshAuthentication-generated Phoenix UI in the router so users can request and confirm magic links via the web, using Swoosh local mailbox in dev.

## Context

Story 0.5 created `User`/`Token` and the magic-link strategy at the resource level; no web surface yet. This story wires the AshAuthentication.Phoenix generator output into `router.ex`. Per architecture §4, Phase 0 does not customize the generator's UI beyond applying gettext to any exposed strings — the generator output is accepted as-is.

## Reference specs

- `/specs/phase-0/architecture.md` §4 (AshAuthentication Phoenix components, route names)
- `/specs/phase-0/architecture.md` §5 (email transport — Swoosh local mailbox in dev)

## Acceptance criteria

- [ ] AC1: `mix ash_authentication_phoenix.install` runs and adds the `AshAuthentication.Phoenix.Router` macro plus auth route scopes to `router.ex`. Verify: `grep -q 'AshAuthentication.Phoenix.Router' lib/ashy_walnut_desk_web/router.ex` and `grep -q sign_in_route lib/ashy_walnut_desk_web/router.ex`.
- [ ] AC2: `GET /sign-in` returns 200 with the magic-link request form (English msgids visible). Verify: connection test in `auth_routes_test.exs` asserts 200 and the presence of an email input.
- [ ] AC3: Submitting a valid email through the sign-in form captures one Swoosh email containing a magic-link URL pointing at the project. Verify: integration test using `Phoenix.LiveViewTest` + `Swoosh.TestAssertions.assert_email_sent/1`.
- [ ] AC4: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

```
test/ashy_walnut_desk_web/auth_routes_test.exs   — connection + Swoosh-capture tests for the auth flow
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex   — add AshAuthentication.Phoenix routes
config/config.exs                    — enable Swoosh.Adapters.Local mailbox preview for dev
config/dev.exs                       — Phoenix dev_routes (if not already enabled) for /dev/mailbox
```

## Implementation notes

- Architecture §4 lists the typical routes (`/sign-in`, `/auth/user/magic_link/:token`, `/sign-out`); verify post-install whether the generator uses these exact names and adjust the test if not.
- The Swoosh local mailbox preview is the dev-mode email viewer; production mailer is deployer-supplied (Phase 5).
- gettext wrapping of generator-exposed strings happens in 0.8 alongside WelcomeLive's strings — this story accepts the English defaults.

## Safety review

- Sensitive records touched? **Yes, indirectly** — sign-in form receives `email`; the request enqueues a `Token`. Both are policy-gated per 0.5.
- AI output to end user possible? **No**.
- Guardrails applied? Policies from 0.5 enforce who can request a magic link (public) and who can read tokens (system only).
- Audit trail covered? Per 0.5's PaperTrail decision.

## Out of scope

- Custom auth UI styling — accept generator defaults.
- Production SMTP adapter — deployer + Phase 5.
- Sign-out UX polish — generator default suffices.

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/auth_routes_test.exs
just dev
# manually: open http://localhost:4000/sign-in, submit your email, check
# http://localhost:4000/dev/mailbox for the captured email
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
