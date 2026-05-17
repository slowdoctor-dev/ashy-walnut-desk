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

**Status**: ✅ resolved by ADR-020 + Story 2.1 implementation.
Historical context below preserved for the audit trail.

**Resolution**: Story 2.1 implementation on
`feat/story-2.1-security-entry-gate` (commit `04472ab`, squash SHA:
`28a0c36`) lands `LiveUserAuth.on_mount(:load_from_cookie)` and
flips `Accounts.User.session_identifier` back to `:jti`, restoring
per-session revocation on the LiveView path.

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

**Status**: ✅ resolved by ADR-021 + Story 2.1 implementation.
Historical context below preserved for the audit trail.

**Resolution**: Story 2.1 implementation on
`feat/story-2.1-security-entry-gate` (commit `04472ab`, squash SHA:
`28a0c36`) adds the `config/runtime.exs` prod block keyed on
`PHX_HOST != "localhost"` and applies `force_ssl: [hsts: true]` plus
secure `session_options` flags at runtime. Dev fallback unchanged.

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

---

## TO-7 — `CompensationAtApproval` uses raw `Repo.query` for the FOR UPDATE lock

**Status**: active, accepted for Phase 2.

**Decision**: `lib/ashy_walnut_desk/interaction/changes/compensation_at_approval.ex`
issues a raw SQL `SELECT … FOR UPDATE` against the `drafts` table
inside its `before_action` hook (and another raw `SELECT` against
the `inboxes`/`conversations` join to resolve the channel id). This
sidesteps Ash's read pipeline and policies for that specific
locking + join.

**Why**: AshPostgres 3.x does not expose row-level pessimistic
locking through Ash queries, and the approval flow must hold a
write-intent lock on the draft row across the Action + Compensation
create steps to defend the per-draft uniqueness invariant against
concurrent approves (proven by `draft_approval_concurrency_test`).
The raw `Repo.query` is the smallest viable workaround.

**What we lose**:
- A second escape from the "all access through Ash" rule (the other
  is `ChainLink`'s prev-hash `FOR UPDATE`, which is structurally
  similar and tested together).
- `AshPaperTrail` does not see this lock, so the policy /
  authorization layer is silently bypassed for those two queries.
  This is currently safe because the queries are read-only (status
  filter + join) and gated by `CompensationAtApproval` only being
  invoked from inside `Draft.:approve`'s change pipeline.

**Compensating controls**:
- Both raw queries run inside the same DB transaction as the
  enclosing Ash action, so the SERIALIZABLE / READ COMMITTED
  guarantees apply.
- Property-style concurrency test
  (`draft_approval_concurrency_test.exs`) and the audit-chain
  concurrency test exercise this path at `n=6` parallel approvals.

**Revisit trigger**: whichever comes first:
1. AshPostgres adds first-class `lock_for_update` support — then
   replace the raw SQL with the typed primitive.
2. A third raw-SQL escape lands in the codebase (the threshold for
   designing a shared `Interaction.Locks` helper).

**Tracking**: hardening-checklist concern; no ADR planned.

---

## TO-8 — `Action.:execute` lifecycle spans CountdownGuard + ExecuteOutbound + ChainLink

**Status**: active, accepted for Phase 2.

**Decision**: `lib/ashy_walnut_desk/interaction/action.ex`'s
`:execute` update action chains three changes — `CountdownGuard`
(elapsed-time check + stashes the loaded draft on context),
`ExecuteOutbound` (resolves adapter, calls `send_outbound/2`, sets
outcome attrs, creates the outbound Message, transitions Inbox via
`:mark_executed`), and `ChainLink` (writes the hash-chained audit
event). The action body itself is empty.

**Why**: Splitting the workflow into composable `Ash.Resource.Change`
modules keeps each step independently testable and lets the same
`ChainLink` change be reused on `record_inbox`, `compose_draft`,
`approve`, and `execute`. The cost is that the `:execute` action
reads as "see the change modules" rather than "here is the
transition."

**What we lose**:
- A reader has to traverse four files
  (`action.ex` → `countdown_guard.ex` → `execute_outbound.ex` →
  `chain_link.ex`) to follow one logical operation.
- Implicit dependency: `ExecuteOutbound` requires
  `CountdownGuard` to have stashed `%{draft: …}` on the context.
  Today this is documented in the moduledoc and validated by the
  existing test suite, but it isn't statically enforced.

**Compensating controls**:
- `ExecuteOutbound.do_send/1` early-exits on
  `Enum.any?(changeset.errors)`, so a missing `CountdownGuard` (or
  a status-validation failure) doesn't crash with
  `Map.fetch!` against `:draft`.
- `HardeningTest` "S3: adapter receives %Message{} struct" pins
  the end-to-end behaviour.

**Revisit trigger**: whichever comes first:
1. A second action grows the same "guard → execute → chain-link"
   shape and we'd want a shared scaffold.
2. The implicit context-stash dependency causes a real bug — at
   which point we elevate the contract to a typed struct (e.g.
   `Interaction.ExecuteContext`) instead of an untyped map key.

**Tracking**: hardening-checklist concern; no ADR planned.

---

## TO-9 — `ChainLink.event_specs/3` for `:draft_approved` re-queries Action + Compensation

**Status**: active, accepted for Phase 2.

**Decision**: `lib/ashy_walnut_desk/interaction/changes/chain_link.ex`
handles the `:draft_approved` event by running two
`Ash.read_one(authorize?: false)` lookups inside its
`after_action`: one for the just-created `Action` row, one for the
just-created `Compensation` row. These exist in memory inside the
calling `CompensationAtApproval.create_action/3` /
`create_compensation/3`, but `ChainLink` doesn't have access to
those local bindings.

**Why**: `ChainLink` is invoked uniformly via
`change({ChainLink, event_type: …})` on every chain step, so it
sees only the record returned by the parent action — for
`:draft_approved`, that's the `%Draft{}`. The sibling Action /
Compensation rows are produced inside a different change
(`CompensationAtApproval`) earlier in the same transaction. There
is no Ash-blessed way to pass arbitrary data from one change to
another except `changeset.context`.

**What we lose**:
- Two extra round-trips per approval (small, but real). Both hit
  unique indexes (`actions_draft_id_index`,
  `compensations_action_id_index`), so they're index-only lookups.
- A correctness footgun: if `CompensationAtApproval` is ever
  re-ordered relative to `ChainLink`, the re-queries silently
  return `{:error, :action_not_found}`. Today the ordering is
  enforced by reading `Draft.:approve` top-to-bottom.

**Compensating controls**:
- Both re-queries run in the same transaction as the parent
  approve action, so they're guaranteed to see the just-inserted
  rows.
- `audit_chain_test.exs` "chain writes five linked events" pins
  the expected event sequence including
  `:compensation_registered`, so a regression here fails fast.

**Revisit trigger**: whichever comes first:
1. A third event type needs to read sibling rows from the same
   transaction — at which point design a typed
   `changeset.context.chain_payload` contract that producing
   changes (`CompensationAtApproval`, etc.) fill in for consumer
   changes (`ChainLink`).
2. Profile data shows the two extra queries materially extending
   approval latency under load.

**Tracking**: hardening-checklist concern; no ADR planned.
