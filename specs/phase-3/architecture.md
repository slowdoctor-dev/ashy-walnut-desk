# Phase 3 — Architecture

> Drafted by the BMAD Architect persona (Claude). Translates
> `specs/phase-3/requirements.md` into resource-level technical design
> + answers Q2-Q5 from the analyst draft as architectural decisions.

## 1. Overview

Phase 3 layers a real-channel integration on top of the Phase 2
four-stage chain. Two new entry points to the chain:

- **Outbound real send**: `Action.execute` schedules an Oban job
  (`Jobs.OutboundSend`) keyed on `action_id`. The job resolves the
  channel adapter (Twilio for `slug: "twilio-sms"`), invokes
  `send_outbound/2` with the resolved `%Message{}`, persists the
  response on `Action.adapter_response`, and writes the
  `:action_executed` audit event. Retries on transient failures
  with exponential backoff; surfaces terminal failures to the
  operator.
- **Inbound webhook ingestion**: `POST /webhook/twilio` validates
  Twilio's `X-Twilio-Signature` header against the request body,
  deduplicates by `MessageSid`, resolves or creates an Identity via
  `InboundIntake`, threads or opens a `Conversation`, creates the
  inbound `Message`, opens an `Inbox` via a new internal
  `:record_inbound` action, and writes a new `:inbound_received`
  audit event.

The `Interaction.Adapter` behaviour from Phase 2 is hardened into
the only provider extension point. A test-only `Adapters.Echo`
fixture runs alongside `Adapters.Twilio` against a single
contract-conformance test, so Phase 6+ providers (WhatsApp, Line,
KakaoTalk) can land as one-file additions.

Compensation invocation (deferred from Phase 2) ships through the
same chain shape: a new `Compensation.:trigger` action mirrors
`Action.:execute` — the same `CountdownGuard` + `ExecuteOutbound`
flow, just keyed off the compensation row instead of the action.
Adds one new audit event type (`:compensation_executed`).

`AuditLive.Chain` (TO-14) lands as an admin-only LV that paginates
`AuditEvent` rows for a chain_topic and renders hash-continuity
status next to each row, mirroring `mix audit.verify`'s output.

```text
                                                      ┌──────────────────────┐
                                                      │   Twilio (external)  │
                                                      └──┬──────────────▲────┘
                                                         │              │
                                            outbound API │              │ inbound webhook
                                                         │              │ X-Twilio-Signature
                                                         ▼              │
                ┌────────────────────────────────────────────────────┐  │
   Oban         │           AshyWalnutDesk.Interaction.Adapters       │  │
   queue        │                                                    │  │
   (outbound,   │   Adapter (behaviour) ◄── Twilio (real)            │  │
    inbound)    │                       └── Echo  (test-only)        │  │
                └────────────────────────────────────────────────────┘  │
                          ▲                              ▲              │
                          │                              │              │
                     send_outbound                  send_outbound        │
                     (countdown OK)                 (compensation)       │
                                                                        ▼
                ┌────────────────────────────────────────────────────────────────┐
                │  AshyWalnutDeskWeb.WebhookController.Twilio                   │
                │   1. Verify X-Twilio-Signature                                │
                │   2. Dedupe by MessageSid (InboundDelivery table)             │
                │   3. InboundIntake.intake/1 → Identity, Conversation, Inbox   │
                │   4. record_message :inbound + record_inbound (Inbox)         │
                │   5. ChainLink → :inbound_received                            │
                └────────────────────────────────────────────────────────────────┘
                          │                              │
                          ▼                              ▼
                    Existing Phase 2 chain (Inbox → Draft → Action → Compensation)
                    plus new Compensation.:trigger path via same adapter.
```

Trade-offs:

- **Oban for outbound retry over inline GenServer.** Oban already
  ships in deps (used by `Token.:expunge_expired`). Adds one
  queue. Inline retry-in-`Action.execute` would block the LV
  request, lose retries on crashes, and complicate the audit
  chain. Cost: Oban worker reads `Action` row, must thread actor /
  context for `record_outbound`'s "internal" policy gates.
- **One new resource (`InboundDelivery`) for dedupe rather than a
  separate Postgres table.** Keeps everything in Ash. Cost: one
  more migration; one more soft-delete-or-immutable decision (we
  pick **immutable**, mirroring `AuditEvent`).
- **Twilio adapter is a thin wrapper over `Req`**, not the
  `ex_twilio` library. Adapter contract stays minimal; we don't
  inherit `ex_twilio`'s ETS-cached client state or its full
  resource graph. Direct HTTP keeps the adapter under 200 lines.
- **Webhook receiver is a controller, not a LiveView.** LV is
  overkill for a fire-and-forget JSON POST; a controller keeps the
  request/response shape tight and skips the LV WS overhead.

## 2. Affected modules

### New (Interaction domain)

```
lib/ashy_walnut_desk/interaction/
├── adapters/
│   ├── twilio.ex                       # real Twilio SMS adapter
│   └── echo.ex                         # test-only conformance fixture
├── changes/
│   ├── inbound_intake.ex               # webhook → chain creation
│   ├── outbound_idempotency.ex         # dedupe by action_id
│   └── compensation_send.ex            # trigger Compensation through chain
├── jobs/
│   └── outbound_send.ex                # Oban worker for Action.:execute
├── inbound_intake.ex                   # Identity-matching + threading logic
├── inbound_delivery.ex                 # Ash.Resource (IMMUTABLE) — dedupe ledger
└── twilio_signature.ex                 # HMAC-SHA1 verifier
```

### New (Web)

```
lib/ashy_walnut_desk_web/
├── controllers/
│   └── webhook/
│       ├── twilio_controller.ex        # POST /webhook/twilio
│       └── twilio_signature_plug.ex    # verifier plug
└── live/
    └── audit_live/
        └── chain.ex                    # admin-only AuditEvent viewer (TO-14)
```

### Modified (existing)

- `lib/ashy_walnut_desk/interaction/inbox.ex` — add `:record_inbound`
  internal action gated by new `Checks.FromInboundWebhook` policy
  check.
- `lib/ashy_walnut_desk/interaction/compensation.ex` — add
  `:trigger` action that mirrors `Action.:execute` (CountdownGuard +
  ExecuteOutbound). Keep `:register` internal-only as before.
- `lib/ashy_walnut_desk/interaction/identity.ex` (Phase 1) — add
  `:provisional?` attribute (default false) and `:register_provisional`
  action gated by `Checks.FromInboundWebhook`.
- `lib/ashy_walnut_desk/interaction/changes/execute_outbound.ex` —
  refactor `attempt_send` to be reusable by both the Action and
  Compensation paths (extract the adapter-call + outcome stamping;
  the Compensation path threads `compensation_id` instead of
  `action_id` for idempotency).
- `lib/ashy_walnut_desk_web/router.ex` — `/webhook/twilio` route on
  a new `:webhook_throttled` pipeline (per-IP throttle, no auth).
- `lib/ashy_walnut_desk_web/live/inbox_live/show.ex` — add
  "Trigger compensation" affordance (admin/operator only) that
  fires `Compensation.:trigger` via the existing countdown UI.
- `config/config.exs` — extend `:channel_adapters` allowlist with
  Twilio.
- `config/runtime.exs` — Twilio credentials from env
  (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`).

### New (Audit)

- New AuditEvent event types: `:inbound_received`,
  `:compensation_executed`.

### New (Specs / Decisions)

- `specs/decisions/ADR-022-twilio-as-first-real-adapter.md`
- `specs/decisions/ADR-023-oban-for-outbound-retry.md`
- `specs/decisions/ADR-024-inbound-intake-policy.md`

### New (Tooling)

- `lib/mix/tasks/phase3.webhook.preflight.ex` — exits non-zero if
  Twilio config missing/invalid; the analyst-AC executable
  preflight gate.

## 3. Ash resources

### 3.1 `Interaction.InboundDelivery` (NEW, immutable)

Dedupe ledger for inbound webhook deliveries. Twilio retries
deliveries until it gets a 2xx; this table is the source of
"already processed" truth.

| Attr | Type | Sensitive | Notes |
|---|---|---|---|
| `id` | uuid | — | |
| `provider` | atom | — | `:twilio`; extensible per future adapter |
| `provider_message_id` | string | — | Twilio's `MessageSid` |
| `received_at` | utc_datetime_usec | — | Server clock at first intake |
| `outcome` | atom | — | `:processed \| :duplicate \| :failed_intake` |
| `intake_failure_reason` | string | — | Nullable; set on `:failed_intake` |
| `created_at` / | utc_datetime_usec | — | (no `deleted_at`) |

Actions: `read` (admin only — operational debugging), `record_delivery`
(internal-only via `FromInboundWebhook` policy check).

Constraint: `unique_index(:inbound_deliveries, [:provider, :provider_message_id])`
so a Twilio retry hits the unique constraint and the controller
returns 200 OK to Twilio without re-creating chain rows.

Retention: 7-day TTL via a new `AshOban` trigger on this resource;
mirrors the daily token expunge pattern.

### 3.2 `Identity.Identity` (MODIFIED)

Add two fields + one action.

| New attr | Type | Sensitive | Notes |
|---|---|---|---|
| `provisional?` | boolean | — | Default `false`. `true` when inbound webhook created the row before any operator confirmation. |
| `discovered_via` | atom | — | Nullable. `:inbound_webhook \| nil`. Set on provisional creates so operator UI can show "this identity was auto-created from an inbound SMS at <timestamp>." |

New action:

- `:register_provisional` — internal-only, gated by
  `Checks.FromInboundWebhook`. Accept list: `[:primary_identifier]`.
  Sets `display_name` from helper
  `Identity.provisional_display_name(identifier)` ("Inbound +1 ***
  1234"), `provisional?: true`, `discovered_via: :inbound_webhook`,
  `notes_summary: nil`.

Operator can later promote a provisional Identity to a confirmed
one via the existing `:edit` action (which becomes "Confirm
identity" in the LV when `provisional? == true`).

### 3.3 `Interaction.Inbox` (MODIFIED)

Add `:record_inbound` action.

```elixir
update :record_inbound, primary?: false do
  accept([:conversation_id, :summary])
  change set_attribute(:status, :open)
  change set_attribute(:recorded_by_id, &system_actor_id/0)
  change(ChainLink, event_type: :inbox_opened)
end

policy action(:record_inbound) do
  authorize_if(FromInboundWebhook)
end
```

Wait — `recorded_by_id` is `attribute_writable? false` per PR #37,
and uses `relate_actor(:recorded_by)`. We can't `relate_actor`
without an actor. Two options:

- **Option A: synthetic system actor.** Reserve a singleton User row
  (`role: :system`, `email: "system@<deployment>"`, registered at
  app boot if missing). `relate_actor(:recorded_by)` works.
- **Option B: relax `attribute_writable?` to `false` for `record_inbox`
  only.** Cumbersome — Ash relationships don't have per-action
  writability.

**Pick A.** New ADR: ADR-024 documents the system actor's scope:
"may only be the actor on `record_inbound`, `record_message :inbound`,
and `record_delivery`; forbidden from any send-path action by the
existing `FromActionExecute` / `FromDraftApprove` gates." A test
asserts the system actor cannot drive `Action.:execute`.

The system actor's email pattern is
`system+inbound@<phx_host>` (matches `:ci_string` validation; the
`+` tag isolates it from real users; the host suffix supports
deployer-instance reuse). Created at app boot via an `Application.start/2`
hook that calls `Accounts.ensure_system_actor/0` — idempotent via
`User.:get_by_email` lookup + create.

### 3.4 `Interaction.Compensation` (MODIFIED)

Add `:trigger` action — the operator-facing entry point that fires
the compensation message through Twilio.

```elixir
update :trigger do
  accept([])
  require_atomic?(false)
  validate({StatusTransition, from: [:registered]})
  change(CountdownGuard)        # same 5s rule per H3
  change(CompensationSend)      # new — analog to ExecuteOutbound
  change({ChainLink, event_type: :compensation_executed})
end

policy action(:trigger) do
  authorize_if(actor_attribute_equals(:role, :admin))
  authorize_if(actor_attribute_equals(:role, :operator))
end
```

`CompensationSend` is a near-clone of `ExecuteOutbound` but uses
`compensation.body` as the message body, sets
`compensation.status: :triggered` + `compensation.triggered_at`,
and uses an idempotency key derived from `compensation_id`.

The `register → triggered → completed` transitions follow the same
pattern Phase 2 designed but didn't implement; this phase ships
`:triggered` (Twilio accepted the send); a follow-on phase can add
`:completed` via Twilio status webhook if needed.

### 3.5 `Interaction.Action` (MODIFIED)

`:execute` action is restructured: instead of inline adapter call,
it schedules an Oban job and returns immediately. The job does the
work. Operator LV stays connected to the same `action_id` and
re-renders when the job marks status `:executed | :failed`.

```elixir
update :execute do
  accept([])
  require_atomic?(false)
  validate({StatusTransition, from: [:pending]})
  change(CountdownGuard)
  change(OutboundIdempotency)   # NEW — stamps action.outbound_idempotency_key
  change(EnqueueOutboundSend)   # NEW — schedules Oban Jobs.OutboundSend
  change({ChainLink, event_type: :action_scheduled})
end
```

New audit event type `:action_scheduled` (chain payload:
`action_id, draft_id, channel_id`).

Oban worker (`Jobs.OutboundSend`):
1. Loads Action + Channel + Draft.
2. Calls `Adapter.send_outbound(message, channel)`.
3. On `{:ok, payload}` — stamps `executed_at`, `adapter_response`,
   `status: :executed`; calls outbound Message create + Inbox
   mark_executed (same as Phase 2 `ExecuteOutbound`'s
   `record_outbound/2`); writes `:action_executed` audit event.
4. On `{:error, :transient}` — Oban retry (default schedule below).
5. On `{:error, :permanent}` — stamps `error`, sets `status:
   :failed`; writes `:action_executed` with `outcome: :failed`.

Action gets a new attribute: `outbound_idempotency_key` (string,
unique). Stamped at `:execute` time, before scheduling. Twilio's
`Idempotency-Key` header carries this UUID; retries pass the same
key.

### 3.6 `Interaction.Channel` (MODIFIED)

Two new fields for Twilio:

| New attr | Type | Sensitive | Notes |
|---|---|---|---|
| `provider_config` | map | — | Nullable. Adapter-specific config (e.g. `%{messaging_service_sid: "MGxxx"}`); validated by adapter at register time. |
| `send_window` | map | — | Nullable. Optional `%{start_hour: 8, end_hour: 20, tz: "UTC"}` for TCPA-style restrictions (Q2). If absent, no time-of-day enforcement. |

Adapter is responsible for validating `provider_config` shape on
register (the existing `AdapterAllowed` validation chain extends).

## 4. LiveView components

### `AuditLive.Chain` (NEW — TO-14 resolution)

Route: `live "/audit/chain", AuditLive.Chain` (admin-only via
`on_mount: [{LiveUserAuth, :live_user_required}, {AuditLive.Chain.AuthCheck, :admin_only}]`).

URL: `/audit/chain?topic=<inbox-uuid>` or `/audit/chain` (default
shows recent chain topics).

Mount:
- `Ash.read(AuditEvent, actor: current_user)` paginated by 50.
- Filter by `chain_topic` (query param).
- For each row, compute hash-continuity status by checking
  `prev_hash` matches the previous row's `hash`. Render a green
  check / red X per row.
- Link to `/audit/chain?topic=<inbox_id>` from each
  `InboxLive.Show` (admin only).

Events: `filter_by_topic`, `verify_chain_now` (re-runs
`AuditChain.walk(topic)` and flashes ok/broken).

### `InboxLive.Show` (MODIFIED)

Add "Trigger compensation" affordance:

- Visible when `inbox.action.status == :executed` AND
  `inbox.compensation.status == :registered`.
- Operator clicks → fires `Compensation.:trigger` via the existing
  `CountdownSendButton` LiveComponent.
- After 5s, the Oban job sends the compensation and the chain
  re-renders showing `Compensation` status `:triggered`.

## 5. External integrations

### 5.1 Twilio REST API (outbound)

- Endpoint: `POST https://api.twilio.com/2010-04-01/Accounts/{ACCOUNT_SID}/Messages.json`
- Auth: HTTP Basic with `ACCOUNT_SID` + `AUTH_TOKEN`.
- Required form fields: `To`, `From` (or `MessagingServiceSid`),
  `Body`. Optional: `StatusCallback` (we set to our
  `/webhook/twilio/status` endpoint for future delivery tracking —
  parsing the callback is in scope; acting on it beyond logging is
  Phase 6+).
- Idempotency: send the same UUID in `Idempotency-Key` header on
  retries. Twilio dedupes within 24 hours.
- Rate limits: 1 msg/sec/number by default; A2P 10DLC raises this
  per registered campaign. Adapter implements no rate limiting at
  the framework level — Oban queue concurrency is the throttle
  knob (`Application.fetch_env!(:ashy_walnut_desk, Oban)[:queues][:outbound]`,
  default 5).
- Error shape: HTTP 4xx with JSON `%{code, message, more_info}`.
  Adapter maps:
  - `429 Too Many Requests` → `{:error, :transient}` (Oban retries)
  - `400 / 21610` (To number unsubscribed) → `{:error, :permanent}`
  - `400 / 21408` (Permission to send to region disabled) → `{:error, :permanent}`
  - `500 / 503` → `{:error, :transient}`
  - Network timeout → `{:error, :transient}`

### 5.2 Twilio webhook (inbound)

- Endpoint: `POST /webhook/twilio` on our side.
- Signature: HMAC-SHA1 of `URL + sorted-form-fields` keyed on
  `AUTH_TOKEN`, sent in `X-Twilio-Signature` header. Verified by
  `TwilioSignaturePlug`. Invalid signatures → 403 + audit (no chain
  rows created).
- Expected fields: `MessageSid`, `From`, `To`, `Body`, `NumMedia`,
  `AccountSid`. Adapter validates `AccountSid` matches our
  configured value.
- MMS (`NumMedia > 0`): out of scope per analyst H5; controller
  drops the media but still records the text body.
- Status callback (`POST /webhook/twilio/status`): same signature
  scheme; logs delivery status (delivered, undelivered, failed) but
  doesn't transition Action/Message rows in Phase 3.

## 6. Data flow

### 6.1 Outbound real send

```text
Operator clicks "Approve & send"
  → Draft.approve (Phase 2 chain; unchanged)
  → CompensationAtApproval creates Action(:pending) + Compensation(:registered)
  → 5s LV countdown elapses
  → InboxLive.Show fires {:execute_action, action_id}
  → Action.:execute:
      validate StatusTransition from: [:pending]
      CountdownGuard      → loads draft, verifies approved_at + 5s
      OutboundIdempotency → stamps action.outbound_idempotency_key = UUID
      EnqueueOutboundSend → Oban.insert(Jobs.OutboundSend, %{action_id})
      ChainLink           → :action_scheduled event
  → return to LV (action.status still :pending; LV polls or PubSub)
  → Oban worker fires (default <1s):
      load Action, Channel, Draft
      adapter = resolve(channel.adapter_module)   # Adapters.Twilio
      result = adapter.send_outbound(message, channel)
      case result do
        {:ok, payload}      → update Action status:executed, adapter_response,
                              executed_at; create outbound Message;
                              Inbox.mark_executed; ChainLink :action_executed
        {:error, :transient} → raise to trigger Oban retry (backoff)
        {:error, :permanent} → update Action status:failed, error;
                               ChainLink :action_executed with outcome:failed
      end
  → operator UI re-renders (Phoenix.PubSub topic "inbox:<id>")
```

Twilio call inside `Adapters.Twilio.send_outbound/2`:
```elixir
def send_outbound(%Message{} = message, %Channel{} = channel) do
  Req.post(
    "https://api.twilio.com/2010-04-01/Accounts/#{account_sid()}/Messages.json",
    auth: {:basic, "#{account_sid()}:#{auth_token()}"},
    headers: [{"Idempotency-Key", message.outbound_idempotency_key}],
    form: [
      To: identity_phone(message),
      From: channel.provider_config["from_number"] || from_number(),
      Body: message.body,
      StatusCallback: status_callback_url()
    ]
  )
  |> case do
    {:ok, %{status: s, body: body}} when s in 200..299 -> {:ok, body}
    {:ok, %{status: 429}} -> {:error, :transient}
    {:ok, %{status: s, body: body}} when s in 400..499 ->
      classify_permanent_or_transient(body)
    {:ok, %{status: s}} when s >= 500 -> {:error, :transient}
    {:error, _} -> {:error, :transient}
  end
end
```

### 6.2 Inbound webhook

```text
Twilio POST /webhook/twilio (form-urlencoded, X-Twilio-Signature)
  → TwilioSignaturePlug:
      verify signature against AUTH_TOKEN
      invalid → 403 + audit (no chain rows)
  → TwilioController.receive_inbound/2:
      check InboundDelivery.exists?(:twilio, MessageSid)
      duplicate → 200 OK (idempotent; no new rows)
      else → InboundIntake.intake/1 in a single DB transaction:
          1. record_delivery(MessageSid, :twilio)
          2. identity = match_or_create_identity(From)
             - existing match by primary_identifier
             - else Identity.:register_provisional + display_name helper
             - ambiguous/malformed → write InboundDelivery
               outcome: :failed_intake + reason; 200 OK to Twilio
               with no chain rows
          3. channel = Channel by slug "twilio-sms"
          4. conversation = thread_or_open(identity_id, channel_id)
             - find most-recent non-archived Conversation on
               (identity_id, channel_id)
             - else open_conversation
          5. inbox = Inbox.:record_inbound(conversation_id, summary)
             via FromInboundWebhook context flag + system actor
          6. message = Message.:record_message(direction: :inbound,
             conversation_id, body, sent_at = received_at)
             via FromInboundWebhook context flag
          7. ChainLink → :inbound_received audit event
      → 200 OK to Twilio
```

`InboundIntake` (the orchestration module) wraps steps 1–7 in
`Repo.transaction/1`. On any failure, transaction rolls back; the
controller responds with 200 OK and the failure is recorded in
`InboundDelivery.outcome = :failed_intake` (a separate, post-
transaction write so the failure is auditable even when the chain
write rolled back). Twilio retries see the duplicate `MessageSid`
and 200-OK without re-processing.

### 6.3 Compensation trigger

```text
Operator clicks "Trigger compensation" on InboxLive.Show
  → Compensation.:trigger:
      validate StatusTransition from: [:registered]
      CountdownGuard      → 5s rule
      CompensationSend    → stamps compensation.outbound_idempotency_key,
                            schedules Oban.Jobs.OutboundSend with
                            kind: :compensation, compensation_id: ...
      ChainLink           → :compensation_executed event
  → Oban worker (same job, different branch):
      load Compensation, parent Action, Channel
      adapter.send_outbound(compensation_message, channel)
      compensation.status :triggered, triggered_at
```

The Oban job's `perform/1` dispatches on the job args `kind:
:action | :compensation`. Both branches share the adapter call
and idempotency logic; only the persistence shape differs.

### 6.4 Identity matching (Q5 default)

```text
Inbound From = "+15551234567"
  → Identity by primary_identifier = "+15551234567"
      found → use it
      not found → register_provisional:
          display_name = provisional_display_name("+15551234567")
                        = "Inbound +1 555 *** 4567"
          primary_identifier = "+15551234567"
          provisional? = true
          discovered_via = :inbound_webhook
```

Masking pattern: keep country code + area code + last 4 digits;
hide middle digits with `***`. For non-US formats: keep first 3 +
mask middle + keep last 4. Sufficient to disambiguate in
operator UI without exposing the full identifier in titles.

Ambiguity / malformed cases (Q5 trailing branch):
- Multiple existing Identities match `primary_identifier` (data
  bug, should not happen with the unique index but we defensively
  check) → `InboundDelivery.outcome: :failed_intake, reason:
  "ambiguous_identity_match"`. No chain rows.
- `From` is empty / malformed (Twilio shouldn't send this but
  defensively) → same shape, `reason: "malformed_identifier"`.
- Both cases surface in an admin LV view (Phase 4+ may add a
  triage queue; Phase 3 just makes them auditable).

## 7. Migration plan

1. `mix ash_postgres.generate_migrations --name phase_3_twilio_axis`
   produces migrations for:
   - `Identity.Identity`: `provisional?` boolean, `discovered_via`
     atom column (`text`-backed).
   - `Interaction.Channel`: `provider_config` jsonb, `send_window`
     jsonb columns.
   - `Interaction.Action`: `outbound_idempotency_key` text +
     unique index.
   - `Interaction.Compensation`: `outbound_idempotency_key` text +
     unique index.
   - `Interaction.InboundDelivery`: new table with composite unique
     index on `(provider, provider_message_id)`.
2. Hand-authored: add the `Accounts.User` system-actor row via a
   versioned data migration. Idempotent (`INSERT … ON CONFLICT (email)
   DO NOTHING`).
3. Oban schema migrations are already in place (Phase 0).
4. No backfill needed for existing Phase 2 chains. Existing
   Conversations / Inboxes keep working; the new fields are
   nullable / default false.

Rollback: `mix ecto.rollback` to pre-Phase-3 timestamp. Removes the
new fields + table. Existing chain rows remain functional.

## 8. Failure modes

| Failure | Degradation |
|---|---|
| Twilio API down | Oban retries with backoff (30s, 2m, 10m, 30m, 2h). On 5th terminal failure: `Action.status: :failed`, error captured, AuditEvent `:action_executed` with `outcome: :failed`. Operator sees the failure in `InboxLive.Show` + can re-approve (creates a new Draft / Action / Compensation chain). |
| Twilio webhook signature invalid | 403 + AuditEvent `:webhook_rejected` (new event type — payload: `provider, reason, message_sid_if_present`). No chain rows. Twilio retries with the same payload; we'll keep rejecting unless config is fixed. |
| Twilio `MessageSid` duplicate | 200 OK without re-processing. The unique index on `InboundDelivery` is the source of truth. |
| `InboundIntake` transaction fails (e.g. DB connection lost mid-write) | Transaction rolls back; controller catches the error and writes `InboundDelivery.outcome: :failed_intake, reason: <inspect(error)>` in a separate transaction; returns 200 OK so Twilio doesn't infinitely retry. Admin sees the failure via `AuditLive.Chain` or the InboundDelivery admin view (defer to Phase 6+ — for now just `iex` access). |
| Oban job for `Action.:execute` crashes mid-send (BEAM termination, network partition, etc.) | On worker restart, Oban re-runs the job. Idempotency key prevents Twilio from double-sending. If the crash happened AFTER Twilio accepted but BEFORE we wrote `Action.status: :executed`, the second attempt gets a `409 Conflict` from Twilio (Idempotency-Key match) with the original response, which we treat as `{:ok, payload}` and proceed. |
| `Compensation.:trigger` adapter call fails | Same retry shape as Action.:execute. Terminal failure → `Compensation.status: :failed`. Operator UI shows the failure; manual re-trigger creates a new Action+Compensation chain (Phase 3 doesn't support partial-retry; full-retry is the right shape per "compensation is a complete message"). |
| Provisional Identity from inbound webhook conflicts with operator-created Identity later | The unique index on `primary_identifier` prevents direct duplicates. If an operator tries to create an Identity that already exists as provisional, they get the existing row + a UI hint "this Identity was auto-created from inbound; promote it." |
| Inbound `From` matches a soft-deleted Identity | `ConversationIdentityAlive` validation rejects new conversation on soft-deleted Identity. Webhook intake records `InboundDelivery.outcome: :failed_intake, reason: "identity_archived"`. Operator must recover the Identity first. |
| System actor row missing at app boot | `ensure_system_actor/0` creates it idempotently. If creation itself fails (e.g. `users_one_admin_idx` conflict for system role), app boot fails — fail-fast is the right shape for a missing prerequisite. |

## 9. Security considerations

### 9.1 Twilio credentials handling

- `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
  read from env in `config/runtime.exs` `:prod` block. Dev/test
  fallback to dev-only constants the same way
  `ASH_AUTHENTICATION_SECRET` does (Phase 2 pattern).
- Prod boot fails if any are missing — analyst-AC executable
  preflight gate (`mix phase3.webhook.preflight`) checks them
  before the deployer ever clicks send.
- `AUTH_TOKEN` flows ONLY through the adapter module and the
  `TwilioSignaturePlug`. Never logged. Never stored on `Channel`
  rows. Never appears in `Action.adapter_response` / `AuditEvent`
  / paper trail.

### 9.2 Webhook authenticity

- Twilio's `X-Twilio-Signature` is HMAC-SHA1 of the canonical URL
  + sorted form fields keyed on `AUTH_TOKEN`. The
  `TwilioSignaturePlug` rebuilds the canonical string from the
  request and compares constant-time.
- Failures → 403 + audit. Failures do NOT consume any database
  rows beyond the AuditEvent.
- Rate limit on `/webhook/twilio` (per-IP throttle on a new
  `:webhook_throttled` pipeline, default 60 req/min) absorbs the
  abuse case where someone discovers the webhook URL and floods it.

### 9.3 Public webhook surface

- The `:webhook_throttled` pipeline applies AshyWalnutDeskWeb's
  existing `Plugs.RateLimit` (extended; same `start_table` +
  `client_ip` logic), with a separate ETS bucket scope so legit
  Twilio traffic doesn't share quota with `/auth/*`.
- Default limit: 60 req/min per IP. Twilio's traffic comes from a
  documented IP range; deployers in their private repo can widen
  the limit for those IPs.
- Webhook URLs are deployer-configurable (publishing the URL to
  Twilio is the deployer's onus). The preflight task checks the URL
  is reachable + responds 200 OK with `Plug.Conn.send_resp/3` for
  the GET probe.

### 9.4 Sensitive data on inbound

- Inbound message bodies are marked `sensitive?(true)` in
  `Message`. Paper trail redacts. AuditEvent payload never carries
  raw body (per Phase 2 §3.8 closed payload contract — new
  `:inbound_received` payload allowlist is `[:message_id,
  :conversation_id, :identity_id, :provider]`).
- Phone numbers (`primary_identifier`) stay raw in `Identity`
  but the masked display name keeps operator UI from leaking
  full numbers in logs / screenshots / titles.

### 9.5 System actor scope

- The system actor (`role: :system`) is created at app boot. It can
  only invoke actions gated by `FromInboundWebhook` context flag
  (per ADR-024). A test asserts the system actor cannot drive
  `Action.:execute`, `Compensation.:trigger`, `Draft.:approve`,
  or any send-path action.
- The system actor's authentication path is locked down: no magic
  link can be requested for `system+inbound@<host>`. The new
  `Accounts.Changes.RegistrationGate` (from PR #38) is extended to
  reject any sign-in attempt targeting `email LIKE 'system+%'`.

## 10. Safety review

Per AGENTS.md §7 (INVIOLABLE rules):

| Rule | Phase 3 coverage |
|---|---|
| §7.1 No domain assertions in AI output without validation | N/A in Phase 3 (AI lands in Phase 4). Existing draft validation surface untouched. |
| §7.2 Human-in-the-loop for ALL sends | Preserved. `Action.:execute` and `Compensation.:trigger` both run through `CountdownGuard` (5s) + operator-initiated trigger. Property test asserts no path creates an outbound `Message` row without a corresponding `Action`/`Compensation` row whose status transitioned via the chain. Oban worker authenticates via the per-job actor context, not via the synthetic system actor (the system actor is only for inbound). |
| §7.3 Audit trail mandatory | Preserved + extended. New event types: `:action_scheduled`, `:action_executed` (already exists; now also written by Oban worker), `:compensation_executed`, `:inbound_received`, `:webhook_rejected`. All five carry closed payload allowlists per the Phase 2 §3.8 contract. `mix audit.verify` walk handles the new types via additive payload contracts. |
| §7.4 Sensitive data handling | Inbound message bodies + identifier marked `sensitive?: true`. Paper trail redacts. Twilio credentials never persisted on resource rows. Raw provider payloads redacted in `Action.adapter_response` (only delivery metadata stored; the raw form body Twilio sent us NEVER lands in DB). |
| §7.5 Disclosure | Honest-framing carry-forward (compensation UI strings continue to fail the `honest_framing_test.exs` if they imply "unsend"). AI-assistance disclosure still N/A (Phase 4). The compensation send carries an automatic "Re: <original conversation subject>" prefix so the recipient sees this is a follow-up; the wording is deployer-overrideable but the default is honest-framing-safe ("Update from <deployment>") — no "we apologize for the previous message" framing in framework defaults; that's a deployer compliance decision. |

## 11. Testing strategy

- **Unit**: Each adapter callback, signature verifier, identity-
  matching helper, threading helper. `Adapters.Echo` is itself
  test-covered as proof-of-shape.
- **Property (StreamData, single-transaction)**:
  - Idempotency: every (action_id, idempotency_key) pair maps to ≤1
    outbound Twilio request.
  - Inbound dedupe: every (provider, message_sid) pair maps to ≤1
    `Inbox` row.
  - Threading: for any sequence of N inbound messages from the same
    `From`, the resulting Conversation count is ≤ the count of
    distinct (identity, channel) pairs.
- **Concurrency**: Parallel inbound deliveries with the same
  MessageSid all return 200 OK; exactly one chain row set is
  created.
- **Adapter contract conformance**: A single test runs both
  `Adapters.Twilio` and `Adapters.Echo` through the same scenarios
  (success, transient error, permanent error). The Twilio side uses
  HTTP request mocking (Req's `Req.Test` plug); the Echo side
  is deterministic.
- **Webhook signature**: positive (valid signature → 200) and
  negative (forged → 403 + audit; replayed body with stale
  signature → still 403). Constant-time comparison verified by
  property test on random byte strings.
- **Compensation trigger**: end-to-end LiveView test sends an
  Action, then operator clicks "Trigger compensation" → after 5s
  countdown, Twilio mock receives the compensation body, chain
  shows `Compensation.status: :triggered`.
- **System-actor scope**: assert system actor cannot invoke
  `Draft.:approve`, `Action.:execute`, `Compensation.:trigger`,
  or any other send-path action; can only invoke
  `FromInboundWebhook`-gated paths.
- **Preflight task**: `mix phase3.webhook.preflight` exits non-zero
  when any of `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, or
  `TWILIO_FROM_NUMBER` is missing. Returns 0 when all present +
  the `Channel{slug: "twilio-sms"}` row exists.
- **Hash chain regression**: `mix audit.verify` exits 0 against a
  fully-driven Phase 3 chain (inbound + outbound + compensation).
- **AuditLive.Chain**: admin can view chain, non-admin gets 403,
  tampering with a row makes the LV mark it broken (matches CLI
  exit code).

## 12. Resolved technical decisions

These were the analyst's open questions (Q2-Q5); resolved here as
architecture decisions.

### Q2 — Compliance envelope (Twilio SMS)

**Decision**: framework ships defaults that satisfy *minimum* US
compliance; deployer overrides per their jurisdiction.

- **A2P 10DLC**: deployer's onus (Brand + Campaign registration
  with The Campaign Registry). Framework doesn't auto-register but
  surfaces an error if Twilio rejects the send with `30007`
  (carrier filtered) by setting `Action.error` to a hint pointing
  at the 10DLC docs.
- **STOP / HELP keywords**: Twilio's messaging service handles these
  automatically when enabled in the deployer's Twilio console; the
  framework adapter reads no `STOP` traffic (Twilio strips it
  before delivery).
- **Time-of-day**: optional `Channel.send_window` field
  (`%{start_hour, end_hour, tz}`); when set, the adapter rejects
  sends outside the window with `{:error, :permanent}` + error
  `"outside_send_window"`. Default: no window (24h sends allowed).
  Deployer narrows per TCPA in their jurisdiction.
- **Opt-in / consent**: out of scope for Phase 3. The framework's
  Consent resource pattern (planned per BASELINE §9, "deferred to
  its first consumer phase") remains deferred. Reasoning: real-
  channel sends in Phase 3 are admin-driven, not auto-triggered;
  there's no implicit "we sent this because an algorithm decided
  to" path that needs consent. Deployers in jurisdictions with
  stricter consent rules (TCPA, GDPR) attach consent rows in their
  private repo.

### Q3 — Retry envelope

**Decision**: Oban-driven 5-attempt schedule.

- Schedule (cumulative wait): **30s, 2m, 10m, 30m, 2h**
- Total budget: ~3h before terminal failure
- Per-attempt timeout (HTTP): 10s
- Terminal failure: `Action.status: :failed`, `Action.error` =
  Twilio's last error string + code; AuditEvent
  `:action_executed` with `outcome: :failed`; operator sees the
  failure in `InboxLive.Show` with no retry button (must re-
  approve via new Draft for safety — replay is operator's choice,
  not automatic).
- Configurable via app env (`config :ashy_walnut_desk,
  Interaction.OutboundSend, max_attempts: 5, …`) so deployers
  can tighten / widen per their SLA.

### Q4 — Inbound dedupe contract

**Decision**: dedupe by Twilio's `MessageSid` with 7-day retention.

- Field: `InboundDelivery.provider_message_id`, unique with
  `provider` per row.
- Retention: 7 days from `received_at`. After that, the dedupe row
  is expired by a daily `AshOban` trigger (mirrors `Token.:expunge_expired`).
  Twilio retries beyond 7 days are extremely rare; if one does
  arrive, it'll be re-processed as a fresh message — a duplicate
  Conversation row will be created, which is auditable but not
  worth defending against beyond 7d.
- Outbound idempotency: `Action.outbound_idempotency_key` is a UUID
  stamped at `:execute` time. Twilio's `Idempotency-Key` header
  takes a UUID; Twilio's own dedup window is 24h.

### Q5 — Provisional Identity naming

**Decision**: deterministic masked-identifier format.

- `display_name`: `"Inbound {format_short(identifier)}"`
  - US-format phone: `"Inbound +1 555 *** 1234"` (country code +
    area code + masked middle + last 4)
  - Other phone formats: `"Inbound +<cc> *** <last 4>"`
  - WhatsApp JID / Line ID / etc. (Phase 6+): `"Inbound <first 3>***<last 3>"`
- `primary_identifier`: full unmasked, sensitive — same as Phase 1.
- `provisional?`: `true`. Operator can promote via existing
  `:edit` action.
- `discovered_via`: `:inbound_webhook` so operator UI can show "auto-
  created from inbound message at <received_at>".
- Format is deployer-overrideable via a behaviour
  (`Identity.ProvisionalNamer`) but defaults to the masked shape
  above.

---

*Architecture drafted by BMAD Architect persona (Claude). Three new
ADRs land in the same PR. When approved, PM persona breaks Phase 3
into the 8-story plan from requirements §4.*
