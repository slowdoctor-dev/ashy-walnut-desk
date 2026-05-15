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

**Status**: ✅ resolved by ADR-020 (Phase 2 prep). Implementing
story is the first Phase 2 story — flips `session_identifier` back
to `:jti` and adds the cookie-loading `on_mount` in the same merge.
Historical context below preserved for the audit trail.

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
issue filed yet (low-priority follow-up). `mix.exs` carries
`{:ash_authentication, "== 4.13.7"}` as an exact pin (not `~>`)
because the worked-around bug is version-sensitive; a future bumper
should confirm the JTI fix landed upstream before relaxing the pin.

---

## TO-2 — Session cookie `secure` flag + `force_ssl` not enforced

**Status**: ✅ resolved by ADR-021 (Phase 2 prep). Implementing
story is the first Phase 2 story (same one that lands ADR-020) —
`config/runtime.exs` prod block keyed on `PHX_HOST != "localhost"`
sets `force_ssl: [hsts: true]` and `secure: true` on the session
cookie. Dev fallback unchanged. Historical context below preserved
for the audit trail.

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

**Status**: ✅ resolved by story 1.8 (commit `7d5d02a`, PR #9).

**Decision** *(historical)*: `lib/ashy_walnut_desk/accounts/token.ex`
defined a `destroy :expunge_expired` action (per the
AshAuthentication.TokenResource extension), but nothing scheduled it.
Surfaced as finding #7 in the Phase 0 security review.

**Why** *(historical)*: Phase 0's focus was authentication
correctness, not operational hygiene. Each magic-link sign-in writes
a Token row; without a sweep, the table grew monotonically.

**Resolution**: Story 1.8 wired an `AshOban.Trigger` on the `Token`
resource scheduled daily that drains expired rows via the existing
`:expunge_expired` destroy action, with a regression test that
asserts an expired token is removed on the next tick (run via
`AshOban.Test.schedule_and_run_triggers/2` against the sandbox).
Required `Oban.testing: :manual` in `config/test.exs` and
`pagination keyset?: true, required?: false` on the trigger's
`read_action` — both captured as gotchas in `AGENTS.md` §10.

---

## TO-4 — Token expunge schedule is hardcoded to 03:00 UTC

**Status**: active, accepted as default.

**Decision**: `lib/ashy_walnut_desk/accounts/token.ex`'s
`AshOban.Trigger :expunge_tokens` uses `scheduler_cron("0 3 * * *")`.
The hour, day-of-week, and TZ are all hardcoded.

**Why**: 03:00 UTC is a defensible off-peak default for most
geographies; this repo is the framework, not a specific deployment,
so picking *some* default is correct and tuning is a deployer
concern per ADR-010.

**What we lose**:
- Deployers in time zones where 03:00 UTC falls during business
  hours (e.g. Asia-Pacific late morning) eat the trigger's
  bulk-destroy on hot Postgres connections.
- No env-var override; tweaking it requires a code change in the
  deployment repo.

**Compensating controls**:
- The expunge action is small (only expired Token rows) and idempotent.
- No real users yet; first deployer will rediscover this immediately.

**Revisit trigger**: the first deployer's hardening story. Either
(a) leave the default and document it as a deployer-overrides-in-
their-repo concern, or (b) move the cron string into
`config/runtime.exs` keyed on an env var (e.g. `TOKEN_EXPUNGE_CRON`)
and update story 1.8's test to read from the same source.

**Tracking**: hardening-checklist concern; no separate ADR planned.

---

## TO-5 — Identity timeline is loaded unbounded, in-memory merged

**Status**: active, accepted for Phase 1 dataset sizes only.

**Decision**: `lib/ashy_walnut_desk_web/live/identity_live/show.ex`'s
`load_timeline/1` issues three independent `Ash.read!` calls
(`Event`, `Appointment`, `Note`) filtered by `identity_id`, with no
`limit` or pagination, then `Enum.sort_by/3` merges them by
timestamp. Each LiveView mount of `IdentityLive.Show` reloads the
full history.

**Why**: Phase 1's `IdentityLive.Show` is the first read surface
that touches multiple Identity-axis resources. The merge is
client-LV-side because Postgres can't `UNION` three Ash resource
queries through Ash 3's read pipeline without giving up policy
checks. A real cross-resource sort + paginate needs either an Ash
calculation or a manual SQL view — both are Phase 2+ shape.

**What we lose**:
- Memory + transfer cost scales linearly with `N_events + M_appointments + K_notes`
  per Identity. For demo data this is fine; at deployer scale (>100
  records per Identity), the LV mount stalls and the BEAM allocates
  the full result set in process heap.
- No `phx-update="stream"` / append behavior — the timeline is a
  static assign re-computed on every change.

**Compensating controls**:
- Identity-axis resources all carry `(:identity_id, :deleted_at)`
  custom indexes (filtering is index-backed).
- No deployer yet; current property tests run against ≤50 records.

**Revisit trigger**: whichever comes first:
1. A deployer reports `IdentityLive.Show` mount > 200 ms with a
   real dataset (≥100 timeline entries).
2. Phase 2 (Interaction-axis messaging) adds a fourth timeline
   resource (Message), pushing the merge cost above the threshold
   where unbounded loading is plausibly fine.

When triggered: design either an `Identity.timeline_page` Ash
calculation backed by a materialized view, or a Phoenix.PubSub
+ LiveView stream approach. New story; new architecture section.

**Tracking**: no ADR yet — design happens at revisit time. Mention
in `AGENTS.md §10` after the design lands.

---

## TO-6 — No prod mailer adapter configured

**Status**: active, accepted as deployer concern.

**Decision**: `config/config.exs` sets
`Swoosh.Adapters.Local` as the global default. `config/dev.exs`
overrides to `Local` (writes to dev mailbox); `config/test.exs`
overrides to `Test` (captures in `assert_email_sent`). There is no
`Mix.env() == :prod` Swoosh block in `config/runtime.exs`. Prod
deploys therefore default to `Local`, which writes the magic-link
email to the local filesystem.

**Why**: magic-link delivery requires a deployer-specific
transactional provider (SMTP credentials, Postmark/Mailgun keys,
Cloudflare email worker, …). The framework cannot pick a sane
default that works without secrets. ADR-010 puts secrets +
provider choice in the deployer's private repo.

**What we lose**:
- A deployer who forgets to add a prod Swoosh adapter sees
  silently-vanishing magic links (the email is written to a
  filesystem path they're unlikely to look at) and a quiet
  inability to onboard any user.
- No CI gate catches this — `Swoosh.Adapters.Local` is a valid
  Swoosh adapter, so the app boots and the test suite passes.

**Compensating controls**:
- `Accounts.Emails.deliver_magic_link/2` returns the standard
  Swoosh `{:ok, _}` from Local, so an explicit smoke test that
  asserts on the *Adapter* name in `Application.get_env(:swoosh)`
  would catch a misconfigured prod boot.

**Revisit trigger**: the first deployer hardening story. Decide
between:
1. A `runtime.exs` prod block that *requires* `SWOOSH_ADAPTER`
   and a provider key, raising at boot if absent (mirrors the
   `IDENTIFIER_HASH_SALT` + `ASH_AUTHENTICATION_SECRET` pattern
   added by the Phase 0 hardening pass).
2. A documented checklist in a future `docs/deployer-setup.md`
   that names "configure a non-Local Swoosh adapter for prod"
   alongside TLS, DNS, and DB.

**Tracking**: hardening-checklist concern; ADR not required.
