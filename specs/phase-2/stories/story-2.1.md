# Story 2.1: Security entry gate (ADR-020 + ADR-021)

**Phase**: 2
**Estimate**: 4h
**Depends on**: —
**Status**: done

---

## Goal

Land the mandatory Phase 2 security gate before any send-path work: cookie-session LiveView user loading (ADR-020), `Accounts.User.session_identifier` flip back to `:jti`, and ADR-021 production TLS/secure-cookie runtime hardening — with `endpoint.ex` switching from compile-time `@session_options` to a runtime-resolved plug so the prod overrides actually take effect.

## Context

This story is an explicit phase gate. No send-related Phase 2 story may merge before this one.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (security dependencies + phase ACs)
- `/specs/phase-2/architecture.md` §9.1–§9.2
- `/specs/decisions/ADR-020-session-loading-via-cookie.md`
- `/specs/decisions/ADR-021-prod-tls-and-cookie-hardening.md`

## Acceptance criteria

- [ ] AC1: LiveView auth path loads current user from cookie session via custom `on_mount` (no dependency on `LiveSession.generate_session/3` subject rebuild). — Verify: `mix test test/ashy_walnut_desk_web/live/live_user_auth_test.exs`
- [ ] AC1b: `on_mount` test covers both LiveView mounts — `LiveView.connected?(socket) == false` (HTTP) and `== true` (WebSocket). A stale or missing session cookie yields `current_user: nil` in both. — Verify: `mix test test/ashy_walnut_desk_web/live/live_user_auth_test.exs` (assert two cases)
- [ ] AC2: `Accounts.User.session_identifier` is set to `:jti` (not `:unsafe`) and existing auth flows remain green. — Verify: `mix test test/ashy_walnut_desk/accounts test/ashy_walnut_desk_web/live`
- [ ] AC2b: The story 0.11 magic-link E2E test passes against the new on_mount: a freshly signed-in user's cookie is correctly loaded by the next LV mount and `current_user.id` matches the registered user. — Verify: `mix test test/ashy_walnut_desk_web/live/magic_link_e2e_test.exs` (or the existing 0.11 E2E test path; story 2.1 implementer locates and asserts it passes)
- [ ] AC3: `endpoint.ex` switches from compile-time `@session_options` module attribute to a runtime-resolved plug (`plug :put_session_options`) so runtime config overrides take effect. `config/runtime.exs` `:prod` block (keyed on `PHX_HOST != "localhost"`) applies `force_ssl: [hsts: true]` and merges `secure: true` + `http_only: true` into `:session_options`. Localhost / dev behavior unchanged. — Verify: `mix test test/ashy_walnut_desk/config/runtime_security_test.exs`
- [ ] AC3b: Integration test pins the HTTP-boundary contract — under prod-like config, the `Set-Cookie` response header for a sign-in includes both `Secure` and `HttpOnly` attributes; under dev config, neither. Pure config assertions can pass even when the endpoint plug change isn't wired; this AC catches that. — Verify: `mix test test/ashy_walnut_desk_web/endpoint_session_cookie_test.exs`
- [ ] AC4: `specs/security/known-trade-offs.md` marks TO-1 and TO-2 resolved with ADR pointers and commit reference. — Verify: `rg -n "TO-1|TO-2|ADR-020|ADR-021" specs/security/known-trade-offs.md`

## Files to create

```
test/ashy_walnut_desk_web/live/live_user_auth_test.exs
test/ashy_walnut_desk/config/runtime_security_test.exs
test/ashy_walnut_desk_web/endpoint_session_cookie_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/user.ex
lib/ashy_walnut_desk_web/live_user_auth.ex
lib/ashy_walnut_desk_web/endpoint.ex
lib/ashy_walnut_desk_web/router.ex
config/config.exs
config/runtime.exs
specs/security/known-trade-offs.md
```

## Safety review

- Sensitive records touched? Authentication/session state only.
- AI output to end user possible? No.
- Guardrails applied? Restores per-session revocation and prod cookie/TLS hardening.
- Audit trail covered? N/A for this infra story.

## Out of scope (will NOT do in this story)

- Interaction-axis resource implementation.
- Any Action/Draft send workflow.

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/live/live_user_auth_test.exs
mix test test/ashy_walnut_desk/config/runtime_security_test.exs
mix test test/ashy_walnut_desk_web/endpoint_session_cookie_test.exs
# Plus: the magic-link E2E test from story 0.11 must continue to pass.
```
