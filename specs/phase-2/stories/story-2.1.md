# Story 2.1: Security entry gate (ADR-020 + ADR-021)

**Phase**: 2
**Estimate**: 3h
**Depends on**: —
**Status**: ready

---

## Goal

Land the mandatory Phase 2 security gate before any send-path work: cookie-session LiveView user loading (ADR-020), `Accounts.User.session_identifier` flip back to `:jti`, and ADR-021 production TLS/secure-cookie runtime hardening.

## Context

This story is an explicit phase gate. No send-related Phase 2 story may merge before this one.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (security dependencies + phase ACs)
- `/specs/phase-2/architecture.md` §9.1–§9.2
- `/specs/decisions/ADR-020-session-loading-via-cookie.md`
- `/specs/decisions/ADR-021-prod-tls-and-cookie-hardening.md`

## Acceptance criteria

- [ ] AC1: LiveView auth path loads current user from cookie session via custom `on_mount` (no dependency on `LiveSession.generate_session/3` subject rebuild). — Verify: `mix test test/ashy_walnut_desk_web/live/live_user_auth_test.exs`
- [ ] AC2: `Accounts.User.session_identifier` is set to `:jti` (not `:unsafe`) and existing auth flows remain green. — Verify: `mix test test/ashy_walnut_desk/accounts test/ashy_walnut_desk_web/live`
- [ ] AC3: `config/runtime.exs` applies `force_ssl: [hsts: true]` + secure session cookie options in `:prod` when `PHX_HOST != "localhost"`, while localhost/dev behavior remains unchanged. — Verify: `mix test test/ashy_walnut_desk/config/runtime_security_test.exs`
- [ ] AC4: `specs/security/known-trade-offs.md` marks TO-1 and TO-2 resolved with ADR pointers and commit reference placeholder. — Verify: `rg -n "TO-1|TO-2|ADR-020|ADR-021" specs/security/known-trade-offs.md`

## Files to create

```
test/ashy_walnut_desk_web/live/live_user_auth_test.exs
test/ashy_walnut_desk/config/runtime_security_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/user.ex
lib/ashy_walnut_desk_web/live_user_auth.ex
lib/ashy_walnut_desk_web/router.ex
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
```
