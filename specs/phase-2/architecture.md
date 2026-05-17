# Phase 2 — Architecture

> Drafted by the BMAD Architect persona (Claude, solo per the
> Codex-out window). Translates `specs/phase-2/requirements.md` into
> resource-level technical design. Phase 1's architecture is the
> structural precedent.

## 1. Overview

Phase 2 builds the **Interaction axis** (How) on top of the Phase 0
foundation and the Phase 1 Identity axis. The four-stage record chain
from ADR-016 — Inbox → Draft → Action → Compensation — lands as Ash
resources with hash-chained `AuditEvent` rows guaranteeing tamper
detection. A `Channel.Adapter` behaviour ships with a no-op stub so
the chain runs end-to-end; the first real adapter is Phase 3.

```text
              ┌────────────────────────────────────────┐
              │   Operator (admin / operator / viewer) │
              └───────────────────┬────────────────────┘
                                  │
                                  ▼
              ┌────────────────────────────────────────┐
              │    AshyWalnutDeskWeb.Endpoint          │
              │  cookie-session on_mount loader (ADR-020) │
              └───────────────────┬────────────────────┘
                                  │
       ┌──────────────────────────┼─────────────────────────┐
       ▼                          ▼                         ▼
  IdentityLive (P1)         InboxLive.*                AuditLive.*
                            Index / Show /             Chain viewer
                            DraftCompose /             (admin-only)
                            CountdownApprove
                                  │
                                  ▼
              ┌────────────────────────────────────────┐
              │   AshyWalnutDesk.Interaction           │
              │   (Ash.Domain)                         │
              └──────┬─────────────────────────────────┘
                     │
   ┌─────────────────┼─────────────────┬─────────────────┐
   ▼                 ▼                 ▼                 ▼
Conversation     Inbox             Draft             Action
   ▼                 ▼                 ▼                 ▼
Message           ChainLink         ChainLink         Compensation
                                                         ▼
                                                    AuditEvent
                                                  (hash-chained,
                                                   immutable)
   │                                                    ▲
   ▼                                                    │
Channel ── delegates to ──► Channel.Adapter.Stub (Phase 2)
                            Channel.Adapter.<Real> (Phase 3+)
                                                    │
                                                    ▼
                              ┌──────────────────────────┐
                              │   AshyWalnutDesk.Identity│
                              │       (Phase 1)          │
                              └──────────────────────────┘
                                            │
                                            ▼
                              ┌──────────────────────────┐
                              │      PostgreSQL 16        │
                              │  8 new tables (4 mutable,│
                              │  3 immutable, 1 mixed)   │
                              └──────────────────────────┘
```

Key shape decisions, with trade-offs:

- **One Interaction domain, two record families.** All Interaction-axis
  resources live in `AshyWalnutDesk.Interaction`. The mutable family
  (Conversation, Message, Inbox, Draft) carries the soft-delete
  pattern from ADR-019. The immutable family (Action, Compensation,
  AuditEvent) has no `deleted_at` and no destroy actions — audit
  chain integrity depends on these rows being permanent.
- **Channel is a thin resource.** `Channel` records the medium
  (`slug`, `display_name`, `adapter_module`) plus an `enabled?` flag.
  Per-channel policy enforcement (service-window rules, template
  approval, rate limits) lives in the adapter module, not the
  resource — same separation `specs/architecture.md §9` already
  documents.
- **The stub adapter is the *only* adapter in Phase 2.** It records
  `Action.status: :executed` without an external API call. Real
  adapters (SMS, email, etc.) land in Phase 3 with their own
  behaviour conformance tests.
- **5-second countdown is server-side** (ADR-013). The
  `Draft.:approve` action sets `approved_at = utc_now()`. The
  `Action.:execute` action checks `NOW() - approved_at >= interval '5 seconds'`
  in a `before_action` change and rejects with a typed error if not.
  No clientside-only animation.
- **AuditEvent hash chain.** Every chain transition writes an
  `AuditEvent` row whose `hash` is `sha256(prev_hash || payload)`.
  Inserts use `SELECT ... FOR UPDATE` on the previous event to
  serialize concurrent writers. Verification is a `mix audit.verify`
  task that walks the chain and exits non-zero on a break.
- **TO-1 (`session_identifier(:unsafe)`) resolved by ADR-020.** A
  custom `on_mount` loads the user from the cookie session directly,
  sidestepping the upstream `LiveSession.generate_session/3`
  jti-prefix-stripping bug. `User.session_identifier` flips back to
  `:jti` and per-session revocation is restored before any Phase 2
  send path ships.
- **TO-2 (session `secure` flag + `force_ssl`) resolved by ADR-021.**
  `config/runtime.exs` gains a `:prod` block keyed on
  `PHX_HOST != "localhost"` that sets `session_options.secure = true`
  and `force_ssl: [hsts: true]`. The dev fallback stays plain HTTP.

## 2. Affected modules

### New (Interaction domain)

```
lib/ashy_walnut_desk/interaction/
├── interaction.ex                       # Ash.Domain
├── conversation.ex                      # Ash.Resource (soft-delete)
├── message.ex                           # Ash.Resource (soft-delete)
├── channel.ex                           # Ash.Resource (soft-delete)
├── inbox.ex                             # Ash.Resource (soft-delete)
├── draft.ex                             # Ash.Resource (soft-delete)
├── action.ex                            # Ash.Resource (IMMUTABLE)
├── compensation.ex                      # Ash.Resource (IMMUTABLE)
├── audit_event.ex                       # Ash.Resource (IMMUTABLE)
├── adapter.ex                           # behaviour
├── adapters/
│   └── stub.ex                          # no-op implementation
├── changes/
│   ├── countdown_guard.ex               # rejects execute if < 5s since approve
│   ├── chain_link.ex                    # writes AuditEvent + hash on transition
│   └── compensation_at_approval.ex      # creates Compensation row at approve
├── validations/
│   ├── conversation_identity_alive.ex   # Conversation FK Identity must not be soft-deleted
│   └── chain_ordering.ex                # enforces valid status transitions
└── audit_chain.ex                       # hash + verify helpers
```

### Modified (existing)

- `lib/ashy_walnut_desk/accounts/user.ex` — flip `session_identifier`
  from `:unsafe` back to `:jti` once ADR-020's custom on_mount is
  wired (see §9).
- `lib/ashy_walnut_desk_web/router.ex` — Phase 2 LiveView routes
  (`/inbox`, `/inbox/:id`, `/audit/chain` admin-only).
- `lib/ashy_walnut_desk_web/live_user_auth.ex` (or equivalent) — the
  new cookie-loading `on_mount` from ADR-020. Replaces (or sits
  alongside) the existing default.
- `config/runtime.exs` — prod block per ADR-021.

### New (Web)

```
lib/ashy_walnut_desk_web/live/inbox_live/
├── index.ex                             # Inbox list (filter by status)
├── show.ex                              # Conversation thread view
├── new.ex                               # Operator-initiated Inbox row
└── chain_component.ex                   # Four-stage chain visualization

lib/ashy_walnut_desk_web/live/audit_live/
└── chain.ex                             # Admin-only hash-chain viewer

lib/ashy_walnut_desk_web/components/
└── countdown_send_button.ex             # Reusable LiveComponent
                                          # (5s server-confirmed countdown)
```

### New (Migrations / config)

- 8 Ash-generated migrations (one per resource).
- 1 hand-authored migration: composite indexes for hash-chain reads
  (`audit_events(prev_hash)`, `audit_events(chain_topic, inserted_at)`).
- `config/runtime.exs` prod hardening block (ADR-021).

### New (Tooling)

- `lib/mix/tasks/audit.verify.ex` — walks `AuditEvent` chain, exits
  non-zero on hash break. Used by `just verify` (added as a new gate
  conditional on the audit_events table existing).
- `priv/scripts/phase2_demo_seed.ex` (or equivalent mix task with
  `Mix.env() in [:dev, :test]` guard — same pattern as
  `phase1.demo.seed`).

### New (Specs)

- `specs/decisions/ADR-020-session-loading-via-cookie.md`
  (resolves TO-1).
- `specs/decisions/ADR-021-prod-tls-and-cookie-hardening.md`
  (resolves TO-2).
- This file (`specs/phase-2/architecture.md`).

### Project-level docs amended by this phase

- `specs/security/known-trade-offs.md` — TO-1 + TO-2 flipped to
  resolved with ADR pointers (kept inline historical wording per
  the TO-3 precedent from PR #15).

## 3. Ash resources

Conventions reused from Phase 1:

- `paper_trail` block with `mixin(AshyWalnutDesk.AdminOnlyVersions)`
  on every mutable resource carrying sensitive state.
- `default_accept([])`; every action declares its accept list
  explicitly.
- Soft-delete pattern (deleted_at + default-filtered :read +
  :read_with_archived admin-only + :archive + :recover) per ADR-019,
  applied to mutable resources only.

### 3.1 `AshyWalnutDesk.Interaction.Conversation`

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `subject` | string | yes | Free text |
| `identity_id` | uuid | — | FK → `identities.id`, on_delete: `:restrict` |
| `channel_id` | uuid | — | FK → `channels.id`, on_delete: `:restrict` |
| `deleted_at` | utc_datetime_usec | — | Soft-delete |
| timestamps | | | |

Actions: `read` (filtered), `open_conversation` (create —
`identity_id` + `channel_id` required; validation rejects if Identity
is soft-deleted), `archive`, `recover`, `read_with_archived`.

Policies: `:viewer` read; `:operator`+`:admin` open + archive;
`:admin` recover + read_with_archived. Same role pattern as Identity.

### 3.2 `AshyWalnutDesk.Interaction.Message`

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `conversation_id` | uuid | — | FK → `conversations.id`, on_delete: `:restrict` |
| `direction` | atom | — | `:inbound \| :outbound` |
| `body` | string | yes | Operator-composed (Phase 2) or AI-generated (Phase 4) |
| `sent_at` | utc_datetime_usec | — | Nullable; set when bound Action executes |
| `approved_by_id` | uuid | — | FK → `users.id`. Non-null when direction `:outbound` (invariant §8.4) |
| `deleted_at` | utc_datetime_usec | — | Soft-delete |
| timestamps | | | |

Actions: `read` (filtered), `record_message` (create —
direction-specific validations), `archive`, `recover`,
`read_with_archived`.

Policies: same as Conversation. Outbound creation gated to actions
that go through the four-stage chain (no direct `record_message`
with `direction: :outbound` from the LV — only from `Action.execute`).

### 3.3 `AshyWalnutDesk.Interaction.Channel`

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `slug` | string | — | Unique, deployer-defined (e.g. `"sms-twilio"`, `"stub"`) |
| `display_name` | string | — | |
| `adapter_module` | string | — | Module name string (looked up at runtime) |
| `enabled?` | boolean | — | Default true |
| `deleted_at` | utc_datetime_usec | — | Soft-delete |
| timestamps | | | |

Actions: `read` (filtered), `register_channel` (create — admin only),
`disable` (set `enabled?: false`), `enable` (set `enabled?: true`),
`archive`, `recover`, `read_with_archived`.

Policies: `:viewer` read; `:admin` only for create/enable/disable
(channels are deployment infra, not operator routine).

Phase 2 deployer-seed creates one row: `slug: "stub"`, pointing at
`AshyWalnutDesk.Interaction.Adapters.Stub`. No others until Phase 3.

### 3.4 `AshyWalnutDesk.Interaction.Inbox`

The first stage of the chain. Operator-initiated in Phase 2.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `conversation_id` | uuid | — | FK → `conversations.id`, on_delete: `:restrict` |
| `status` | atom | — | `:open \| :drafting \| :executed \| :dismissed` (ADR-016) |
| `summary` | string | yes | One-line operator description of the intent |
| `recorded_by_id` | uuid | — | FK → `users.id`, set via `relate_actor` |
| `deleted_at` | utc_datetime_usec | — | Soft-delete |
| timestamps | | | |

Actions: `read` (filtered), `open_inbox` (create — `:open`),
`start_drafting` (transitions to `:drafting`; writes AuditEvent),
`mark_executed` (transitions to `:executed`; called only from
`Action.execute`), `dismiss`, `archive`, `recover`,
`read_with_archived`.

Policies: same role pattern as Conversation.

### 3.5 `AshyWalnutDesk.Interaction.Draft`

The second stage. Operator-composed in Phase 2; AI-filled in Phase 4.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `inbox_id` | uuid | — | FK → `inboxes.id`, on_delete: `:restrict` |
| `body` | string | yes | Proposed message text (operator-composed in P2) |
| `compensation_body` | string | yes | Remediation text authored alongside the draft (ADR-016: "what would remediation look like?") |
| `status` | atom | — | `:drafting \| :approved \| :superseded \| :rejected` |
| `approved_at` | utc_datetime_usec | — | Set by `:approve`; used by countdown guard |
| `approved_by_id` | uuid | — | FK → `users.id`. Non-null when `status == :approved` |
| `ai_prompt` | string | yes | **Nullable in P2; required in P4** |
| `ai_model` | string | — | **Nullable in P2; required in P4** |
| `ai_response` | string | yes | **Nullable in P2; required in P4** |
| `ai_validator_output` | map | — | **Nullable in P2; required in P4** |
| `deleted_at` | utc_datetime_usec | — | Soft-delete |
| timestamps | | | |

Actions: `read` (filtered), `compose_draft` (create — `:drafting`;
requires `body` and `compensation_body`), `revise` (update body /
compensation_body; only while `:drafting`), `approve` (transitions
to `:approved`; sets `approved_at` + `approved_by_id` via
`relate_actor` + `:approved_by`; triggers
`CompensationAtApproval` change which creates the Compensation row;
writes AuditEvent), `reject`, `supersede`, `archive`, `recover`,
`read_with_archived`.

Policies: `:operator`+`:admin` compose / revise / approve / reject;
`:admin` recover.

### 3.6 `AshyWalnutDesk.Interaction.Action`

The third stage. **Immutable** — no soft-delete, no destroy.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `draft_id` | uuid | — | FK → `drafts.id`, on_delete: `:restrict`, **unique** (one Action per Draft) |
| `channel_id` | uuid | — | FK → `channels.id`, on_delete: `:restrict` |
| `status` | atom | — | `:pending \| :executed \| :failed \| :rolled_back` |
| `adapter_response` | map | — | Adapter's return payload (stub adapter returns `%{stub: true}`) |
| `executed_at` | utc_datetime_usec | — | Set on success |
| `error` | string | — | Set on failure |
| `created_at` / `updated_at` | | | (no `deleted_at`) |

Actions: `read`, `execute` (the actual send — guarded by
`CountdownGuard` change). No update/destroy from the LV; status
transitions only via `execute` (`:pending → :executed/:failed`) or
the future Phase 3 `roll_back`.

Policies: `:operator`+`:admin` execute; `:viewer` read. No archive,
no recover.

### 3.7 `AshyWalnutDesk.Interaction.Compensation`

The fourth stage. **Immutable** for the same reasons as Action.
Created automatically at Draft approval time by the
`CompensationAtApproval` change (ADR-016: "always create
Compensation, even if never invoked").

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `action_id` | uuid | — | FK → `actions.id`, on_delete: `:restrict`, **unique** |
| `status` | atom | — | `:registered \| :triggered \| :completed \| :failed` |
| `body` | string | yes | Copied from `Draft.compensation_body` at registration |
| `triggered_at` | utc_datetime_usec | — | Nullable in Phase 2 (invocation UI is Phase 3) |
| `created_at` / `updated_at` | | | (no `deleted_at`) |

Actions: `read`, `register` (called internally by
`CompensationAtApproval`; not callable from LV). Phase 2 ships no
`trigger` action — that's Phase 3. Status transitions deferred.

Policies: `:viewer` read; only-from-internal-change for create.

### 3.8 `AshyWalnutDesk.Interaction.AuditEvent`

Immutable, hash-chained log of every chain transition.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `chain_topic` | string | — | `"inbox:<uuid>"` — groups events for one chain instance |
| `event_type` | atom | — | `:inbox_opened \| :draft_started \| :draft_approved \| :action_executed \| :compensation_registered` (extensible per phase) |
| `subject_kind` | atom | — | `:inbox \| :draft \| :action \| :compensation` |
| `subject_id` | uuid | — | Polymorphic FK (no DB FK; integrity checked by `mix audit.verify`) |
| `actor_id` | uuid | — | FK → `users.id`. Nullable for system-initiated events |
| `payload` | map | — | Event-specific JSON (e.g. `{"status": "approved"}`) |
| `prev_hash` | string | — | hex sha256 of previous event in `chain_topic`, or `nil` for genesis |
| `hash` | string | — | hex sha256 of `prev_hash || canonical_payload` |
| `inserted_at` | | | (no `updated_at`, no `deleted_at`) |

Actions: `read` (admin only), `record_event` (called only via
`ChainLink` change; never from LV directly).

Policies: `:admin` read; only-from-internal-change for create. No
update, no destroy, no archive.

Concurrency: writers acquire `SELECT ... FOR UPDATE` on the latest
event for the same `chain_topic` before computing `hash`. See §6.4.

## 4. LiveView components

### `InboxLive.Index`
Lists Inbox rows filtered by status (open / drafting / executed /
dismissed). Pagination via Ash keyset pagination. Admin toggle for
soft-deleted rows.

### `InboxLive.Show`
Displays the full chain for one Inbox: Conversation context, Inbox
metadata, current Draft (composer if status `:drafting`), Action
status, Compensation row. Uses `ChainComponent` for the
visualization band at the top.

### `InboxLive.New`
Operator-initiated Inbox creation. Takes an `identity_id` (linked
from `IdentityLive.Show`) and creates a Conversation +
Inbox in one server-side transaction.

### `InboxLive.ChainComponent` (LiveComponent)
Single component that renders all four chain stages as a stepper.
Sole owner of the chain-visualization UI per requirements §2 ("a
single chain-visualization component"). Inputs: the Inbox struct
plus its preloaded Draft, Action, Compensation. Renders the
"honest framing" copy from the gettext catalog — no UI strings
imply "unsend."

### `Components.CountdownSendButton` (LiveComponent)
Server-confirmed 5-second countdown. Renders a button that, on
click, fires `:approve` immediately and starts a server-tracked
timer; only the `:execute` action 5s later actually sends. The
countdown UI display is decorative — the server guard (§6.3) is
authoritative.

### `AuditLive.Chain` (admin-only)
Renders a paginated view of `AuditEvent` rows for a given
`chain_topic`, with hash-continuity highlighting. Bound to
`mix audit.verify`'s output format so the UI matches the CLI.

## 5. The `Channel.Adapter` behaviour

```elixir
defmodule AshyWalnutDesk.Interaction.Adapter do
  @callback send_outbound(message :: %Message{}, channel :: %Channel{}) ::
              {:ok, map()} | {:error, term()}
  @callback channel_slug() :: String.t()
end
```

Phase 2 ships exactly one implementation:

```elixir
defmodule AshyWalnutDesk.Interaction.Adapters.Stub do
  @behaviour AshyWalnutDesk.Interaction.Adapter

  @impl true
  def channel_slug, do: "stub"

  @impl true
  def send_outbound(_message, _channel), do: {:ok, %{stub: true}}
end
```

Phase 3's first real adapter (deployer-influenced choice — likely
SMS via Twilio or messaging via WhatsApp Business) will add a second
implementation and refine the behaviour as needed. Resist
designing for SMS/email/etc. now.

## 6. Data flow

### 6.1 Open Inbox (operator-initiated)

```text
Operator clicks "Open Inbox" on IdentityLive.Show
  → POST handle_event "open_inbox" with %{identity_id, summary}
  → Conversation.open_conversation(identity_id, channel: stub_channel)
  → Inbox.open_inbox(conversation_id, summary)
  → ChainLink change writes AuditEvent (event_type: :inbox_opened,
    prev_hash: nil, hash: sha256(canonical))
  → push_navigate to InboxLive.Show
```

### 6.2 Compose + approve Draft

```text
Operator types in CountdownSendButton's composer
  → submit "compose_draft" with %{body, compensation_body}
  → Draft.compose_draft → status: :drafting
  → AuditEvent written (event_type: :draft_started)
  → operator clicks "Approve & send"
  → submit "approve_draft"
  → Draft.approve runs:
       1. CompensationAtApproval change creates Compensation
          (status: :registered, body: copied from compensation_body)
       2. Draft.status → :approved, approved_at = now()
       3. AuditEvent for :draft_approved
       4. AuditEvent for :compensation_registered
  → CountdownSendButton starts the 5s server-side timer
  → after 5s, Process.send_after fires Action.execute
```

### 6.3 Action execute (countdown-guarded)

```text
Action.execute runs (5s after :approve)
  → CountdownGuard change checks
    (NOW() - draft.approved_at) >= interval '5 seconds'
    via expr() against the loaded Draft
    → if not, returns {:error, :countdown_violation}
  → Channel.Adapter resolved from channel.adapter_module
  → adapter.send_outbound(message, channel) called
  → stub returns {:ok, %{stub: true}}
  → Action created with status: :executed,
    executed_at = now(), adapter_response = %{stub: true}
  → Inbox.mark_executed (status → :executed)
  → Message record created with direction: :outbound,
    approved_by_id (copied from draft), sent_at = now()
  → AuditEvent for :action_executed
```

### 6.4 AuditEvent insert (concurrency)

```text
ChainLink change runs in a DB transaction:
  1. SELECT id, hash FROM audit_events
       WHERE chain_topic = ?
       ORDER BY inserted_at DESC
       LIMIT 1
       FOR UPDATE        -- serializes concurrent writers
  2. prev_hash = (row.hash || nil)
  3. canonical = Jason.encode(payload, sort_keys: true)
  4. hash = :crypto.hash(:sha256, (prev_hash || "") <> canonical)
            |> Base.encode16(case: :lower)
  5. INSERT INTO audit_events (chain_topic, event_type, ...,
                                prev_hash, hash) VALUES (...)
```

Property test (StreamData): N concurrent operators approve drafts
on the same Inbox chain; assert (a) all events have valid hash
links to their declared `prev_hash`, (b) walking the chain from
genesis reaches all events, (c) `mix audit.verify` exits 0.

## 7. Migration plan

1. Hand-authored migration enabling the `audit_events`
   composite indexes (chain_topic + inserted_at; prev_hash).
   *Earlier timestamp than Ash-generated migrations so the indexes
   are in place when Ash creates the table.*
2. `mix ash_postgres.generate_migrations --name phase_2_interaction_axis`
   produces 8 resource migrations.
3. Seed: insert the `stub` Channel row via a versioned data
   migration (separate from Ash's structural migration so deployers
   can replace the seed in their private repo).
4. No backfill needed — Phase 1 tables remain untouched.

Rollback: `mix ecto.rollback` to the pre-Phase-2 timestamp. No
custom rollback steps; Ash handles all 8 resources.

## 8. Failure modes

| Failure | Degradation |
|---|---|
| `CountdownGuard` rejects Action.execute because clock skew makes `approved_at` look future | Treat clock skew > 1s as a hard failure (alerts ops); reject the execute and force operator to re-approve |
| Concurrent approvals on same Inbox race the AuditEvent insert | `SELECT … FOR UPDATE` serializes; one writer wins, the loser sees a typed `:chain_conflict` error and retries idempotently |
| Stub adapter returns error (shouldn't, but defensive) | `Action.status: :failed`, error captured, AuditEvent for `:action_executed` carries `payload.outcome: :failed` |
| Operator dismisses an Inbox mid-drafting | `Inbox.dismiss` sets status `:dismissed`; any in-flight Draft is `:rejected`; AuditEvent for both transitions |
| Compensation creation fails inside the `Draft.approve` transaction | Entire approve transaction rolls back; Draft stays `:drafting`; operator retries |
| Hash chain breaks (manual DB tampering) | `mix audit.verify` exits non-zero on the first broken link, printing the chain_topic + event id; CI gate fails the build if run against the dev DB |
| `Channel.adapter_module` references an unloaded module | `Action.execute` rejects with typed `:channel_misconfigured` error; admin alerted |

## 9. Security considerations

### 9.1 TO-1 resolution: cookie-loading on_mount (ADR-020)

Phase 0's `session_identifier(:unsafe)` was the accepted trade-off
to work around `ash_authentication_phoenix`'s
`LiveSession.generate_session/3` stripping the `<jti>:` prefix. With
Phase 2 shipping the first privileged send surface, that trade-off
is no longer acceptable.

Resolution: a custom `on_mount` callback in
`AshyWalnutDeskWeb.LiveUserAuth` loads the user from the cookie
session directly (`get_session(socket, :user_token)` →
`AshAuthentication.subject_to_user/2`), bypassing
`LiveSession.generate_session/3` entirely. `User.session_identifier`
flips back to `:jti`, restoring per-session JWT revocation. See
ADR-020 for the full reasoning.

This must land before any send-related story (2.x) ships. Story
ordering enforces it: the on_mount + jti flip is Phase 2's first
story.

### 9.2 TO-2 resolution: prod cookie + force_ssl (ADR-021)

`config/runtime.exs` `:prod` block:

```elixir
if System.get_env("PHX_HOST", "localhost") != "localhost" do
  config :ashy_walnut_desk, AshyWalnutDeskWeb.Endpoint,
    force_ssl: [hsts: true],
    session_options:
      [secure: true]
      |> Keyword.merge(Application.get_env(:ashy_walnut_desk, :session_options, []))
end
```

Dev (`PHX_HOST` unset or `localhost`) keeps plain HTTP. Prod (real
hostname) gets `force_ssl` + `secure` cookie. Test env is
unaffected. See ADR-021 for the full reasoning.

### 9.3 Send authorization

The four-stage chain enforces that every outbound `Message` carries
`approved_by_id`:

- `Action.execute` is the only action that creates outbound
  Messages (Message.record_message rejects `direction: :outbound`
  unless invoked from `Action.execute`'s context).
- `Action.execute` copies `approved_by_id` from the parent Draft.
- `Draft.approve` sets `approved_by_id` via `relate_actor(:approved_by)`.
- Therefore the actor who clicks "Approve & send" is the
  approver-of-record. No path bypasses this.

### 9.4 Hash-chain integrity

- Postgres-level: `audit_events` has no UPDATE or DELETE actions
  exposed. Direct SQL UPDATE/DELETE can still corrupt the chain —
  `mix audit.verify` is the detection mechanism. Future story:
  Postgres trigger that rejects `UPDATE` or `DELETE` at the DB
  level (deferred to Phase 3 hardening unless deployer asks).
- Application-level: every chain-writing change runs inside a
  transaction with `SELECT … FOR UPDATE` on prev event.
- Tamper response: `mix audit.verify` non-zero exit. No automatic
  "self-heal" — chain corruption is an alarm condition.

### 9.5 Sensitive-data handling

- `Message.body`, `Draft.body`, `Draft.compensation_body`,
  `Inbox.summary`, `Conversation.subject`, `Draft.ai_prompt`,
  `Draft.ai_response` all marked `sensitive? true`.
- PaperTrail with `:redact` on all of the above (same Phase 0
  pattern that protected `User.email`).
- `AuditEvent.payload` is a map; sensitive fields are stored as
  `"<redacted>"` in the canonical hashed form (so the hash still
  proves "this transition happened" without exposing content).

## 10. Safety review

Per AGENTS.md §7 (INVIOLABLE rules):

| Rule | Phase 2 coverage |
|---|---|
| §7.1 No domain assertions in AI output without validation | N/A — no AI in Phase 2. Draft schema reserves the AI metadata columns so Phase 4 doesn't add columns; validator integration deferred. |
| §7.2 Human-in-the-loop for ALL sends | `Action.execute` is reachable only via `Draft.approve` → `CountdownSendButton`. No autonomous path exists. Property test asserts `Action` rows without a `Draft.approved_by_id` predecessor are unreachable. |
| §7.3 Audit trail mandatory | `AuditEvent` writes on every chain transition. Hash chain verifiable via `mix audit.verify`. |
| §7.4 Sensitive data handling | Marked + PaperTrail-redacted per §9.5. Raw `body` content never enters AuditEvent payload (only status / metadata). |
| §7.5 Disclosure | N/A — no AI in Phase 2. Phase 4 wires the disclosure footer on AI-generated drafts. |

## 11. Testing strategy

- **Unit**: each Ash action, each `change` module, each behaviour
  callback. The `CountdownGuard` gets its own test that forges
  `approved_at` to recent timestamps and asserts rejection.
- **Integration** (LiveView): the full chain open-inbox →
  compose → approve → execute end-to-end, run against
  `Channel.Adapter.Stub`.
- **Property** (StreamData): chain invariants — every Action has a
  Compensation; every Compensation has an Action; hash continuity
  holds under N concurrent approvers; chain replays are
  deterministic.
- **Audit chain verification**: `mix audit.verify` exits 0 against
  the test DB after every chain integration test. CI gate added
  to `just verify`.
- **Playwright**: screenshots of each chain stage (open Inbox,
  drafting, countdown, executed). Same pattern as Phase 1, lives
  under `docs/phase-2-screenshots/`.

## 12. Open technical questions

- [ ] **`Process.send_after` for the 5s server timer — is the timer
  authoritative or just convenience?** Proposed: the timer is
  convenience (fires the `:execute`), but `CountdownGuard`'s
  `approved_at` check is the authoritative gate. If the LV process
  dies during the 5s, the operator must re-trigger; the guard still
  prevents a sub-5s execute.

- [ ] **AuditEvent canonical payload encoding — `Jason` with sorted
  keys, or a custom canonicalizer?** Proposed: `Jason.encode!(payload,
  pretty: false)` with map keys pre-sorted via a `payload_canonical/1`
  helper. Sufficient for SHA-256 stability; switch to RFC 8785
  if/when a deployer requests stricter canonical JSON.

- [ ] **Database-level prevention of `UPDATE`/`DELETE` on
  `audit_events`?** Proposed: defer to a Phase 3 hardening story.
  `mix audit.verify` is the Phase 2 detection mechanism; DB
  triggers add complexity the framework doesn't yet need.

---

*Architecture drafted by BMAD Architect persona (Claude, solo per
the Codex-out window). TO-1 + TO-2 resolutions written as
ADR-020 + ADR-021 in the same PR. When approved, PM persona breaks
Phase 2 into stories.*
