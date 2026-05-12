# Story 0.8: WelcomeLive + gettext for Phase 0 strings

**Phase**: 0
**Estimate**: 1.5h
**Depends on**: 0.7
**Status**: ready

---

## Goal

Implement `AshyWalnutDeskWeb.WelcomeLive` at `/` showing the project name, application version, and a sign-in link (unauthenticated) or the current user's email + sign-out link (authenticated). All user-facing strings flow through gettext; English `.po` is populated.

## Context

Architecture §4.1 specifies WelcomeLive's mount data, events, and components. Architecture §6.2 specifies the render flow. Phoenix's gettext backend was generated in Story 0.1; this story is where it actually gets used. The session/user lookup uses the AshAuthentication-mounted helpers from Story 0.7.

## Reference specs

- `/specs/phase-0/architecture.md` §4.1 (WelcomeLive contract)
- `/specs/phase-0/architecture.md` §6.2 (welcome render flow)
- `/AGENTS.md` §10 (gotcha: `mount/3` runs twice — HTTP + WebSocket)

## Acceptance criteria

- [ ] AC1: Route `/` maps to `AshyWalnutDeskWeb.WelcomeLive`. Verify: `grep -q 'live "/", WelcomeLive' lib/ashy_walnut_desk_web/router.ex` (or equivalent live route entry).
- [ ] AC2: Rendered page contains the project name string ("ashy-walnut-desk") and the version returned by `Application.spec(:ashy_walnut_desk, :vsn)`. Verify: LiveView test asserts both via `render/1`.
- [ ] AC3: Unauthenticated visitor sees a "Sign in" link pointing to the AshAuthentication sign-in route. Verify: LiveView test asserts the link href.
- [ ] AC4: Authenticated user sees their email and a "Sign out" link. Verify: LiveView test signs a user in (test helper) and asserts both elements appear.
- [ ] AC5: All user-facing strings in WelcomeLive flow through gettext; the English `.po` contains the new msgids after extraction. Verify: `mix gettext.extract && grep -q "Welcome" priv/gettext/en/LC_MESSAGES/default.po`.

## Files to create

```
lib/ashy_walnut_desk_web/live/welcome_live.ex          — root LiveView
test/ashy_walnut_desk_web/live/welcome_live_test.exs   — render + auth-state tests
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                 — map "/" to WelcomeLive
priv/gettext/en/LC_MESSAGES/default.po             — extracted msgids
```

## Implementation notes

- WelcomeLive's `mount/3` is side-effect-free: reads compile-time constant for the project name, `Application.spec/2` for the version, session for the optional user. Safe under the double-mount per AGENTS.md §10.
- The test helper for the authenticated case can fixture a `User` via `Accounts.register_with_magic_link` + manually-completed token, or use AshAuthentication's test helpers if available.

## Safety review

N/A — WelcomeLive shows authenticated user's own email only; no sensitive data leak path. Already-marked `sensitive? true` attributes are not exposed beyond the user themselves.

## Out of scope

- Customizing AshAuthentication-generated screens — those keep generator look-and-feel (Story 0.7 mounted them).
- Inbox/Identity/Knowledge/Overview LiveViews — later phases.
- Non-English locales — deployer concern (Phase 5).

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/live/welcome_live_test.exs
just dev
# manually: visit http://localhost:4000 — see project name + version + Sign in
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
