# Phase 3 security hardening — summary

> An iterative, alternating-author security review run after Phase 3
> shipped. 14 [3.sec] PRs merged (#56–#68). Converged on two
> consecutive clean rounds. This file is the operator-facing record:
> what was found, what was fixed, and what stayed in the "audited
> clean" column.

---

## Process

- **Trigger:** Phase 3 introduced a real outbound channel (Twilio
  SMS) and a public webhook endpoint. The new surface needed a
  pass beyond the per-story acceptance criteria.
- **Method:** alternating-author audit. Claude and Codex each take a
  round (one PR per round). The off-rotation agent reviews, then
  becomes the on-rotation agent. Each PR keeps the
  one-PR-at-a-time rule. CI must be green.
- **Stop condition:** two consecutive rounds with no real
  exploitable finding. Codex went over its weekly quota at round
  16, so the final confirmation was Claude-on-Claude with a
  deliberately different attack-surface list each round.

## PR-by-PR

Numbered by round. Some rounds didn't ship a PR — listed as
**no-finding** if the round audited clean. Round 11 was a false
"no-finding" caught in round 12; that lesson shaped the
stop-condition above.

| PR | Round | Author | Closed |
|----|-------|--------|--------|
| [#56](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/56) | 1 | Claude | `AuditEvent.payload :sensitive?`, `safe_return_to/1` tightened, webhook throttle 60→20 req/min/IP, system-actor scope tests for Phase 3 actions |
| [#57](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/57) | 2 | Codex | `Jobs.OutboundSend` refuses unscheduled state (Oban injection); rate-limiter no longer trusts `X-Forwarded-For` by default; worker re-checks channel adapter against the allowlist before dispatch |
| [#58](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/58) | 3 | Claude | Twilio signature URL pinned via `TWILIO_WEBHOOK_URL` (not `conn.host`); body fields capped at 2000 chars; `Identity.primary_identifier` requires E.164 |
| [#59](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/59) | 4 | Codex | Worker + Twilio failure-path logs switched from `inspect(reason)` to sanitized reason tags |
| [#60](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/60) | 5 | Claude | `Identity.primary_identifier` field policy admin-only — closed a regression introduced by #58 (the new raw E.164 was viewer-readable) |
| [#61](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/61) | 6 | Codex | Field policies on `Message.body` / `Compensation.body` / `Inbox.summary` / `Conversation.subject`; `primary_identifier_hash` admin-only; unique DB index on `identities.primary_identifier_hash` + race handling in `:register_provisional` |
| [#62](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/62) | 7 | Claude | Field policies on `Action.adapter_response` / `Action.error` / `Compensation.adapter_response` / `Compensation.error` — Twilio response carries the recipient phone under `"to"` |
| [#63](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/63) | 8 | Claude | Field policies on `Draft.body` / `Draft.compensation_body` (Codex was rate-limited) |
| [#64](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/64) | 9 | Claude | `Plug.Parsers` body cap reduced from default 8 MB → 200 KB to bound memory-DoS |
| [#65](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/65) | 10 | Codex | Field policies on `Channel.adapter_module` and on Identity-axis timeline bodies (`Event` / `Appointment` / `Note`) |
| — | 11 | Claude | **False no-finding** — pass missed Draft AI artifacts, caught by round 12 |
| [#66](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/66) | 12 | Codex | Field policies on `Draft.ai_prompt` and `Draft.ai_response` (Phase 4 fields already in the schema) |
| [#67](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/67) | 13 | Claude | Field policies on `Draft.ai_model` and `Draft.ai_validator_output` — sibling pair to #66 |
| [#68](https://github.com/slowdoctor-dev/ashy-walnut-desk/pull/68) | 14 | Codex | Defensive scaffolding — explicit but behaviour-preserving field policies on `User.email`, `AuditEvent.payload`, `InboundDelivery.provider_message_id`. Largely no-op |
| — | 15 | Claude | **Clean** across 8 surfaces |
| — | 16 | Claude | **Clean** across 10 different surfaces (Codex weekly quota exhausted before independent confirmation; resumes 2026-05-24) |

## What was found (themes)

**Theme 1: information disclosure via `public?: true` + lenient
resource policy.**

Most of the PR series (rounds 5–8, 10, 12, 13, 14) was field-level
exposure. Ash's `sensitive?: true` flag redacts `inspect/2` and
paper-trail diffs, but does **not** restrict `Ash.read/2`
output — viewers admitted by the resource-level `:read` policy still
get the value in API responses. The fix pattern, repeated across
seven resources:

```elixir
field_policies do
  field_policy :the_sensitive_field do
    authorize_if(actor_attribute_equals(:role, :admin))
    authorize_if(actor_attribute_equals(:role, :operator))
  end

  field_policy :* do
    authorize_if(always())
  end
end
```

Fields gated across the series: `Identity.primary_identifier` /
`Identity.primary_identifier_hash`, `Message.body`,
`Compensation.body` / `.adapter_response` / `.error`,
`Inbox.summary`, `Conversation.subject`,
`Action.adapter_response` / `.error`, `Draft.body` /
`.compensation_body` / `.ai_prompt` / `.ai_response` / `.ai_model` /
`.ai_validator_output`, `Channel.adapter_module`, plus the Identity
timeline bodies on `Event` / `Appointment` / `Note`.

**Theme 2: infrastructure-level fail-safes.**

- Webhook throttle lowered from 60 to 20 req/min/IP (round 1).
- Rate-limiter stopped trusting `X-Forwarded-For` by default
  (round 2).
- Twilio credentials fail-fast at boot in `:prod` (round 3).
- Twilio signature URL pinned to deployer config (round 3) to
  remove `Host:` from the canonical HMAC string.
- POST body cap reduced from 8 MB to 200 KB (round 9).
- Oban worker refuses to run against an unscheduled `Action`
  (round 2) and re-validates the channel adapter against the
  allowlist before dispatch.

**Theme 3: input validation and persistence shape.**

- `Identity.primary_identifier` now requires E.164 after a
  normalization step that strips formatting characters (round 3).
- Message / Draft / Compensation body strings capped at 2000
  chars (round 3).
- Inbound dedupe ledger insert moved to the start of the intake
  transaction to convert a duplicate-as-failure misreport into a
  clean `:duplicate` outcome under concurrent webhook delivery
  (round 6, building on the [3.fix] race-fix series).

**Theme 4: log-emission discipline.**

Round 4 swept the Oban worker and Twilio adapter and replaced
`Logger.warning("error: #{inspect(reason)}")` calls with sanitized
reason tags. Reason: rolled-back changesets carry full attribute
maps, which `inspect/2` would dump verbatim into structured logs
that get shipped offsite.

## What was audited clean (rounds 15–16)

These attack surfaces were examined and produced no real exploit:

- Email enumeration via magic-link request (the strategy returns
  `:ok` for known and unknown emails alike).
- Session fixation (`:jti` rotation per ADR-020 + presence-checked
  on every request).
- Concurrent operator approvals on the same Draft (Ash action
  policy + `set_attribute` semantics, no integrity break).
- `ProvisionalNamer.name/1` side-channel (deterministic masking,
  no extra info leaked).
- AshOban trigger actor handling (nil actor stays nil, policies
  still apply).
- LiveView event handler authorization (every `handle_event` that
  mutates state re-checks at the Ash action layer).
- `mix audit.verify` output (UUIDs only, no raw sensitive data).
- Race on `primary_identifier_hash` with different `MessageSid`s
  but same `From` (the unique DB index added in round 6 is the
  source of truth — only a test-coverage gap remained, not an
  exploit).
- LiveView uploads (no `allow_upload` calls in the codebase).
- Process-dictionary leaks across requests (no `Process.put/get`
  in `lib/`).
- Logger metadata sensitivity (no module sets sensitive content
  on the metadata).
- 5-second countdown clock-skew (forward-jump allows early send,
  backward-jump DoS-on-self — operational-NTP concern, not an
  attacker-controlled vector).
- Atom-creation attacks (`String.to_existing_atom/1` call sites
  are guarded).
- Calculations / aggregates leaking past field policies (none
  exposed sensitive fields).
- Cookie session flags (`same_site: "Lax"` baseline,
  `http_only: true` + `secure: true` merged in `:prod`).
- `Phoenix.HTML.raw/1` bypass (zero call sites in `lib/`).
- Registration-gate plumbing (env var → app config →
  `RegistrationGate` change all aligned).
- `Identity.discovered_via` constraint (`one_of: [:inbound_webhook]`,
  no bypass).

## Open items deliberately not fixed

- **5-second countdown vs server clock skew.** Operational concern,
  not an exploit. Deployers run NTP. No PR opened.
- **Race-on-different-`MessageSid`s test coverage.** The unique
  index in #61 makes the race safe, but a property test asserting
  exactly-one-Identity-per-`From` under high concurrency is not
  yet written. Not a security gap; testing debt.
- **Codex Round 16 confirmation.** Codex hit its weekly plan
  quota mid-round-16; can retry 2026-05-24. The Claude-only
  R15+R16 pair used deliberately disjoint surface lists as a
  best-effort substitute. If round 16 (Codex) lands and finds
  something, the iteration reopens.

## Why this file exists

A 14-PR series with this much overlap is hard to review by reading
the PRs in sequence — the field-policy story stretches across
seven PRs that each only touch one resource. This summary is the
single page a new reviewer can read instead.

It also documents the iteration protocol so a future hardening
sweep (say, after Phase 4 ships the AI-drafts feature) can run
the same alternating-author loop with the same stop condition.
