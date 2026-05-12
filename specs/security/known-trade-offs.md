# Known security trade-offs

Trade-offs deliberately accepted at a given phase, with an explicit
revisit trigger. The point of this file is to keep documented
decisions visible — not buried in code comments — so they get
revisited on schedule rather than calcifying into "the way we do it".

Add new entries at the bottom. Each entry gets a stable heading so
ADRs and stories can link to it. Remove an entry only when the
trade-off has been resolved (and record the resolution in the
corresponding commit / ADR).

---

## TO-1 — `User.session_identifier(:unsafe)` instead of `:jti`

**Status**: active, accepted for Phase 0 only.

**Decision**: `lib/ashy_walnut_desk/accounts/user.ex` sets
`session_identifier(:unsafe)`. Set by commit `85c6bfb` (story 0.8).

**Why**: `ash_authentication_phoenix` v2.16.0's
`LiveSession.generate_session/3` rebuilds the LiveView session from
`conn.assigns.current_user` via
`AshAuthentication.user_to_subject/1`, which drops the `<jti>:`
prefix. The downstream `on_mount(:default)`'s `split_identifier/2`
then can't recover the user for resources with
`session_identifier(:jti)`, so the LV mounts with `current_user=nil`
even after a valid sign-in. See AGENTS.md §10 gotchas.

**What we lose**:
- Per-session JWT revocation. A leaked JWT remains valid until its
  natural expiry (default 14 days).
- DB-side sign-out: `AshAuthentication.Phoenix.Plug.clear_session/2`
  → `revoke_session_tokens/3` silently no-ops for `:unsafe` resources.
  The session cookie is cleared, but no revocation row is written.

**Compensating controls (Phase 0)**:
- No real users yet, no production deployment.
- No privileged "operator" actions yet — first phase that ships
  privileged surface is Phase 2 (messaging).
- Token lifetime can be shortened if Phase 1 lands before this is
  resolved (default 14 days → e.g. 1 day via
  `authentication.tokens.token_lifetime`).

**Revisit trigger**: whichever comes first:
1. Upstream fix in `ash_authentication_phoenix` that preserves the
   `<jti>:` prefix through `generate_session/3`. Then flip back to
   `:jti` and re-run the story 0.8 test suite.
2. Start of Phase 2 (Interaction-axis messaging — session theft
   becomes materially exploitable). At that point, either upstream is
   fixed, or we set `require_token_presence_for_authentication? true`
   and store sessions in the Token resource, or we write a custom
   on_mount that loads the user from the cookie session directly.

**Tracking**: an ADR will be drafted at revisit time. No upstream
issue filed yet (low-priority follow-up).
