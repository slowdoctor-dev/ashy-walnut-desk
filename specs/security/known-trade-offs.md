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

---

## TO-2 — Session cookie `secure` flag + `force_ssl` not enforced

**Status**: deferred to the first deployer's hardening story.

**Decision**: `lib/ashy_walnut_desk_web/endpoint.ex`'s `@session_options`
does not set `secure: true`, and `config/runtime.exs`'s prod block
does not enable `force_ssl: [hsts: true]`. Surfaced as finding #6 in
the Phase 0 security review.

**Why**: dev and test environments don't have TLS. Flipping
`secure: true` unconditionally breaks local dev (cookies stop being
sent over `http://localhost`). The Cloudflare Tunnel path (the
documented self-host route in BASELINE §12) terminates TLS at the
tunnel, so the Phoenix endpoint itself can run plain HTTP — but the
session cookie must still be marked secure end-to-end. This is a
deployment-config decision per ADR-010, not a framework decision.

**Compensating controls (Phase 0)**:
- `same_site: "Lax"` already set on the session cookie.
- No real users / no production deployment.
- BASELINE §12 names "Domain + TLS" as a deployer responsibility.

**Revisit trigger**: the first real deployer's hardening story. They
must set `secure: true` (and `http_only: true`, which Plug.Session
defaults to) in their deployment-specific endpoint override, and
enable `force_ssl` in `runtime.exs`'s prod block. Alternatively, if
we ship a default-on prod hardening pass before any deployer
engages, do it in `config/runtime.exs`'s `:prod` block keyed on
`PHX_HOST != "localhost"` (so the dev fallback keeps working).

**Tracking**: no separate ADR — this is hardening-tasks territory.
Will be a Phase 1+ story or part of the deployer-instance README.

---

## TO-3 — `Token` resource has no scheduled expunge of expired rows

**Status**: deferred to Phase 1.

**Decision**: `lib/ashy_walnut_desk/accounts/token.ex` defines a
`destroy :expunge_expired` action (per the AshAuthentication.TokenResource
extension), but nothing schedules it. Surfaced as finding #7 in the
Phase 0 security review.

**Why**: Phase 0's focus was authentication correctness, not
operational hygiene. Each magic-link sign-in writes a Token row;
without a sweep, the table grows monotonically. For Phase 0 with no
real users this is invisible.

**Compensating controls (Phase 0)**:
- Magic-link tokens have a short lifetime (10 min by default).
- No real users → table stays small.
- `mix ash_postgres.generate_migrations --check` keeps the schema
  honest, so we'll notice if Token grows weird columns.

**Revisit trigger**: Phase 1, when Identity-axis resources start
referencing Token (or earlier if a first deployer engages). The
shape is a small story: add an AshOban trigger or an Oban Cron
entry in `runtime.exs` calling
`Ash.bulk_destroy(Token, :expunge_expired, %{}, authorize?: false)`
daily. Includes a regression test that an expired token is destroyed
on the next sweep tick.

**Tracking**: candidate story for `specs/phase-1/stories/`. Title
suggestion: "Daily expunge of expired authentication tokens via
AshOban trigger".
