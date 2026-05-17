# ADR-021: Prod TLS + secure-cookie hardening keyed on `PHX_HOST` (resolves TO-2)

**Status**: Accepted
**Date**: 2026-05-15
**Deciders**: Phase 2 user + Architect (Claude Opus 4.7) under Codex-out solo coverage.

---

## Context

Phase 0 surfaced finding #6 in the Phase 0 security review: the
session cookie has no `secure: true` flag and `config/runtime.exs`'s
prod block does not enable `force_ssl: [hsts: true]`. The
trade-off was accepted as TO-2 in `specs/security/known-trade-offs.md`:
"deferred to the first deployer's hardening story."

The reasoning was sound at the time. Phase 0 had no real users and
no privileged operator surface. Dev and test don't have TLS;
flipping `secure: true` unconditionally would break local dev
(cookies stop being sent over `http://localhost`). The Cloudflare
Tunnel path documented in BASELINE §12 terminates TLS at the tunnel,
so the Phoenix endpoint itself can run plain HTTP — but the session
cookie must still be marked secure end-to-end.

Phase 2 changes the threat model:

- Session theft was a theoretical concern in Phase 0; in Phase 2,
  a stolen session can approve outbound sends (`approved_by_id` on
  every Message per ADR-016 + invariant §8.4).
- TO-1 (`session_identifier(:unsafe)`) is being closed in the same
  Phase 2 prep PR via ADR-020. Closing one cookie-related trade-off
  while leaving another open is incoherent.
- The first deployer's hardening story is not yet scheduled; if
  the framework ships Phase 2 with TO-2 still open, the framework
  itself acquires a non-trivial "configure this in your deployer
  repo or be exposed" footgun.

TO-2's documented revisit options:

1. **Deployer-config only** — the deployer sets `secure: true` and
   `force_ssl` in their private repo's endpoint override. (Status
   quo. Forces every deployer to remember.)
2. **Default-on prod hardening in `config/runtime.exs`** keyed on
   `PHX_HOST != "localhost"` so the dev fallback keeps working.

## Options considered

### Option 1: Stay deferred to first deployer

- Pros: no framework code change; matches ADR-010's "deployer
  owns deployment config."
- Cons:
  - TO-2 was filed as a Phase 0 security finding, not a
    deployment-config preference. The framework shipping with a
    known-bad default after Phase 2's send surface goes live is
    indefensible by AGENTS.md §7.4.
  - First deployer hasn't been scheduled; "until then" is unbounded.
  - Closing TO-1 while leaving TO-2 open invites confusion about
    which session-cookie concerns the framework now handles.

### Option 2: Framework default-on, dev fallback via `PHX_HOST`

- Pros:
  - The right default lands before the first deployer arrives,
    so deployers inherit safety instead of having to remember.
  - Dev (`PHX_HOST` unset or `"localhost"`) keeps working over
    plain HTTP.
  - Implementation is one `if` block in `config/runtime.exs` and
    a small endpoint config change.
  - Mirrors the existing Phase 0 pattern of "prod env-var guards
    that raise on missing secrets" — same idea, applied to
    cookie/TLS posture.
- Cons:
  - A deployer who serves a non-`localhost` host without actual
    TLS in front (rare — Cloudflare Tunnel etc. terminate TLS
    by default) will break their own setup. The `force_ssl`
    behaviour redirects all HTTP → HTTPS; a deployer running
    HTTP-only behind a non-tunnel proxy is misconfigured.
  - We have to document the `PHX_HOST` knob clearly so a deployer
    debugging a "cookies missing" issue knows where to look.

## Decision

We chose **Option 2: framework default-on hardening keyed on
`PHX_HOST`**.

Reasoning:

- Phase 2 makes session theft materially consequential. Leaving
  TO-2 open while closing TO-1 in the same Phase 2 prep PR is a
  half-measure.
- The framework picking a safe default for prod, with an explicit
  dev fallback, is consistent with the Phase 0 hardening pass that
  added `raise` guards for missing `IDENTIFIER_HASH_SALT` and
  `ASH_AUTHENTICATION_SECRET` in `:prod`. Same shape: "the
  framework refuses to ship insecure defaults to prod even if the
  deployer hasn't configured them yet."
- ADR-010 ("deployer owns deployment config") is not violated:
  the deployer still owns `PHX_HOST` and the choice of TLS
  termination. The framework just makes the safe-default choice
  for them when `PHX_HOST` indicates a real host.

Implementation requires **three coordinated changes** (the original
draft of this ADR had a circular `Application.get_env`-inside-
`config` sketch — corrected here via the R1 review).

```elixir
# config/config.exs — base defaults stored in app env
config :ashy_walnut_desk, :session_options,
  store: :cookie,
  key: "_ashy_walnut_desk_key",
  signing_salt: System.get_env("SESSION_SIGNING_SALT") || "dev-only-salt",
  same_site: "Lax"

# config/runtime.exs `:prod` block
if System.get_env("PHX_HOST", "localhost") != "localhost" do
  base = Application.get_env(:ashy_walnut_desk, :session_options, [])

  config :ashy_walnut_desk, :session_options,
    Keyword.merge(base, secure: true, http_only: true)

  config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
    force_ssl: [hsts: true]
end

# lib/ashy_walnut_desk_web/endpoint.ex — replace
#   plug Plug.Session, @session_options
# with a runtime-resolved plug:
plug :put_session_options
defp put_session_options(conn, _opts) do
  opts =
    Application.fetch_env!(:ashy_walnut_desk, :session_options)
    |> Plug.Session.init()

  Plug.Session.call(conn, opts)
end
```

The `endpoint.ex` change is the load-bearing piece. Without it,
`@session_options` is baked in at compile time and no `runtime.exs`
override can take effect.

Test coverage (story 2.1):

- Config test: `PHX_HOST=desk.example.com` → app env contains
  `secure: true, http_only: true`; endpoint config has
  `force_ssl: [hsts: true]`.
- Config test: `PHX_HOST=localhost` (or unset) → base session
  options only, no `secure`, no `force_ssl`.
- **Integration test (S1/A3 review findings):** make an HTTP request
  to the endpoint under prod-like config and assert the `Set-Cookie`
  response header includes `Secure` and `HttpOnly` attributes. Pure
  config asserts can pass even if the plug change isn't wired
  correctly; the integration test pins the actual cookie flag at
  HTTP boundary.

## Consequences

### Positive

- Default prod posture is safe. A deployer who deploys with
  `PHX_HOST=desk.example.com` and any TLS terminator gets
  `force_ssl` + `secure` cookie out of the box.
- TO-2 in `specs/security/known-trade-offs.md` flips to
  "resolved with pointer to this ADR."
- Closes the Phase 2 session-cookie story in one go: TO-1 (cookie
  loading + JWT revocation) via ADR-020, TO-2 (cookie + TLS posture)
  via ADR-021.

### Negative / accepted trade-offs

- A deployer who serves a non-`localhost` host over plain HTTP
  (no tunnel, no proxy) breaks their setup. This is misuse, not
  failure: HTTP-only public deployments of a regulated-services
  communications platform are not the supported configuration.
  Documented in the deployer-setup notes (to be written when the
  first deployer onboards — out of scope for this ADR).
- `PHX_HOST` becomes a load-bearing env var. Its current
  documentation (BASELINE §12 "Domain + TLS — Cloudflare Tunnel
  is the easy path") needs a small amendment in a follow-up to
  call out the runtime-config behaviour.

### Follow-up actions

- [ ] First Phase 2 story (the same one that lands ADR-020) adds
      the `config/runtime.exs` prod block and the two unit tests.
- [ ] Update `specs/security/known-trade-offs.md` TO-2 to status
      "resolved" with pointer to this ADR and the implementing
      commit (same pattern as TO-3 in PR #15).
- [ ] Future doc PR: amend BASELINE §12 deployment requirements
      to call out the `PHX_HOST != localhost` knob.

## References

- Related ADRs: ADR-005 (human approval required), ADR-010
  (deployment-as-private-repo — confirms this is framework-default,
  not deployer-policy). ADR-020 (cookie-loading on_mount — TO-1) is
  the companion ADR in the same Phase 2 prep PR.
- `specs/security/known-trade-offs.md` TO-2 (the trade-off this
  ADR resolves).
- Phase 0 hardening pattern for prod env-var guards
  (`config/runtime.exs`'s `IDENTIFIER_HASH_SALT` +
  `ASH_AUTHENTICATION_SECRET` raise blocks).
- `specs/phase-2/architecture.md §9.2` (integration detail).
