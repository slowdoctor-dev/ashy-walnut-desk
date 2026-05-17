# ADR-020: Load LiveView user from cookie session (resolves TO-1)

**Status**: Accepted
**Date**: 2026-05-15
**Deciders**: Phase 2 user + Architect (Claude Opus 4.7) under Codex-out solo coverage.

---

## Context

Phase 0 set `AshyWalnutDesk.Accounts.User.session_identifier(:unsafe)`
(commit `85c6bfb`, story 0.8) as an accepted trade-off (TO-1 in
`specs/security/known-trade-offs.md`). The upstream cause was
`ash_authentication_phoenix` v2.16.0's `LiveSession.generate_session/3`,
which rebuilds the LiveView session from `conn.assigns.current_user`
via `AshAuthentication.user_to_subject/1` and drops the `<jti>:`
prefix. The downstream `on_mount(:default)`'s `split_identifier/2`
then can't recover the user for resources with `session_identifier(:jti)`,
so the LV mounts with `current_user=nil`. `:unsafe` worked around it
at the cost of per-session JWT revocation.

Phase 0's compensating control was "no real users, no privileged
operator actions yet — first privileged surface is Phase 2." That
revisit trigger is now live: Phase 2 ships outbound sends with
`approved_by_id` (the operator who clicks "Approve & send"). A
leaked JWT under `:unsafe` would allow an attacker to approve and
send messages on the victim's behalf for up to 14 days (the token
default lifetime), with no DB-side revocation possible.

TO-1's documented revisit options:

1. **Upstream JTI fix landed** → flip back to `:jti`, re-run the
   story 0.8 test suite. (We checked: as of 2026-05-15 no upstream
   patch exists for `LiveSession.generate_session/3`. Waiting is
   not viable.)
2. **Custom `on_mount` that loads from cookie session directly,
   bypassing `LiveSession.generate_session/3`.**
3. **Short-lived tokens + re-auth on every send action** (a
   compensating control that mitigates the symptom without fixing
   the cause).

## Options considered

### Option 1: Wait for upstream fix

- Pros: zero work; eventual normal upstream behaviour.
- Cons: no signal upstream is working on it; we'd ship Phase 2 with
  `:unsafe` still in place. Indefensible per ADR-005 + TO-1's own
  trigger.

### Option 2: Custom cookie-loading `on_mount`

- Pros:
  - Sidesteps the upstream bug entirely. We don't depend on a
    `LiveSession.generate_session/3` fix.
  - Restores per-session JWT revocation (`User.session_identifier`
    flips back to `:jti`).
  - Implementation surface is small: one `on_mount/4` function plus
    a config update on the LiveView socket pipeline.
  - No friction on the operator UX. Sign-in still works the same way.
- Cons:
  - We own one more piece of auth glue. If upstream eventually
    fixes the bug, we have to decide whether to keep our loader
    (probably yes — explicit beats inherited) or remove it.
  - The cookie-loading path must not silently fall back to "no
    user" on a bad cookie. Test coverage required.

### Option 3: Short-lived tokens + re-auth on every send

- Pros: doesn't require flipping `session_identifier`; works around
  the symptom.
- Cons:
  - Operator UX degrades sharply ("re-enter your email to send each
    message"). Hostile for the demo flow and likely for real use.
  - Doesn't restore JWT revocation; only narrows the leak window.
  - More complex than Option 2 because it requires a new auth flow
    step, not just a cookie reader.

## Decision

We chose **Option 2: custom cookie-loading `on_mount`**.

Reasoning:

- It restores the original Phase 0 design intent (`:jti`-keyed
  per-session revocation) without depending on an upstream fix
  we can't influence.
- The implementation is small enough that the testing surface is
  manageable: one cookie-read path, one fallback (no user), one
  expired-token path.
- It removes the most pressing compensating-control assumption
  from TO-1 ("no privileged surface yet") before Phase 2 ships the
  first privileged surface.

Implementation sketch (**indicative only** — story 2.1 implementer
confirms the exact `ash_authentication` 4.13.7 API surface against
hex docs; the function/module names below may not match verbatim).
See `specs/phase-2/architecture.md §9.1` for the full integration:

```elixir
defmodule AshyWalnutDeskWeb.LiveUserAuth do
  # Indicative — verify the actual API at implementation time.
  # Candidate paths: AshAuthentication.subject_to_user/2,
  # AshAuthentication.Plug.Helpers.retrieve_from_session/2, or the
  # token-based load via Accounts.Token + AshAuthentication.Jwt.
  def on_mount(:load_from_cookie, _params, session, socket) do
    case session do
      %{"user_token" => token} ->
        case load_user_from_token(token) do
          {:ok, user} ->
            {:cont, Phoenix.Component.assign(socket, :current_user, user)}

          _ ->
            {:cont, Phoenix.Component.assign(socket, :current_user, nil)}
        end

      _ ->
        {:cont, Phoenix.Component.assign(socket, :current_user, nil)}
    end
  end
end
```

See AGENTS.md §10's existing gotcha on
`ash_authentication_phoenix` `LiveSession.generate_session/3`
jti-stripping for the trap surface that motivated this ADR.

Wire-up: every LiveView that previously used
`AshAuthentication.Phoenix.LiveSession`'s default `on_mount` switches
to `on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}`.

`Accounts.User.session_identifier` flips from `:unsafe` back to
`:jti` in the same story. TO-1 is marked resolved in
`specs/security/known-trade-offs.md` with a pointer to this ADR
and the implementing commit.

## Consequences

### Positive

- Per-session JWT revocation restored. A signed-out user's token
  cannot be reused.
- Phase 2's send-authorization story (every outbound Message carries
  `approved_by_id`) is no longer undermined by a leaked-token risk.
- The auth flow becomes explicit about how the LV process learns
  the user — easier to audit, easier to test.
- Future LV authentication concerns (e.g. role-aware redirects)
  hook into our `on_mount`, not a third-party helper.

### Negative / accepted trade-offs

- We own one more piece of auth glue. The `LiveUserAuth.on_mount`
  implementation must stay correct across `ash_authentication`
  upgrades. Mitigation: a test that asserts the on_mount loads a
  freshly signed-in user, a test that asserts it gracefully handles
  a stale cookie, and a test that asserts it does not regress to
  `current_user=nil` after a `LiveView.connected?` boundary.
- **Phoenix LiveView mounts twice per page load** — once over HTTP
  (full conn context), once over WebSocket (only session arg + LV
  params). Our `on_mount` receives `session` as an arg in both
  invocations, so the read path is uniform. But tests **must** cover
  both: `LiveView.connected?(socket) == false` (HTTP) and `== true`
  (WebSocket). A bug that only manifests on the WebSocket mount
  (e.g. session-arg shape difference, missing key) will pass a
  single-mount test silently. Story 2.1 AC requires explicit
  coverage of both paths.
- If upstream eventually fixes `LiveSession.generate_session/3`,
  we have to decide whether to keep our loader (recommended) or
  remove it. Captured as a Phase 2 retrospective question.
- One more place to remember when adding a new LiveView. Mitigated
  by surfacing it in `prompts/bmad-architect.md` as a Phase 2+ checklist
  item.

### Follow-up actions

- [ ] First Phase 2 story implements the `on_mount` + flips
      `session_identifier` to `:jti` + adds the three tests above.
      Must merge before any send-related story.
- [ ] Update `specs/security/known-trade-offs.md` TO-1 to status
      "resolved" with pointer to this ADR and the implementing
      commit (same pattern as PR #15 resolved TO-3).
- [ ] Phase 2 retrospective: did the upstream
      `LiveSession.generate_session/3` bug get fixed? If yes, do we
      remove our loader or keep it as explicit auth?

## References

- Related ADRs: ADR-005 (human approval required), ADR-013
  (5-second countdown). ADR-021 (prod TLS + cookie hardening — TO-2)
  ships alongside this in the same Phase 2 prep PR.
- `specs/security/known-trade-offs.md` TO-1 (the trade-off this
  ADR resolves).
- `AGENTS.md §10` gotcha for `ash_authentication_phoenix`
  `LiveSession.generate_session/3` jti-stripping (existing).
- `specs/phase-2/architecture.md §9.1` (integration detail).
