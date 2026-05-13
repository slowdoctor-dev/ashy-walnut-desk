# Architecture

> Project-level architecture. Immutable for the life of v1.
> Phase-level designs in `/specs/phase-N/architecture.md`.

---

## 1. System overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          Overview Layer                          │
│            (read-only aggregator, operator entry point)          │
└─────────────────────┬───────────────────────────────────────────┘
                      │
       ┌──────────────┼──────────────┐
       │              │              │
   ┌───▼────┐    ┌────▼────┐    ┌────▼────┐
   │IDENTITY│◀──▶│INTERACT │◀──▶│KNOWLEDGE│
   │ Who/   │    │  How    │    │  What   │
   │ When   │    │         │    │         │
   └────────┘    └─────────┘    └─────────┘
       │              │              │
       └──────────────┼──────────────┘
                      │
            ┌─────────▼─────────┐
            │  Meta-Operations  │
            │     (sideways,    │
            │ invisible to most)│
            └───────────────────┘
```

## 2. Three coequal axes

### Identity (Who/When)

Identity, history, scheduling.

- `Identity` — the client/customer record
- `Event` — what happened (service rendered)
- `Appointment` — when (covers both future scheduling and post-encounter follow-ups via an `appointment_type` enum; FollowUp is not a separate resource)
- `Note` — operator observations
- `Consent` — legal record *(deferred to first consumer phase; see `specs/phase-1/architecture.md §3.5` for the current rationale and the candidate append-only-ledger design)*

### Interaction (How)

Multi-channel messaging.

- `Conversation` — a thread
- `Message` — single exchange
- `Channel` — the medium (deployer chooses; messaging / email / etc.)
- `Draft` — AI-generated, awaiting approval
- `Template` — pre-approved auto-responses

### Knowledge (What)

Domain expertise as ontology.

- `Manual` — how-to knowledge
- `Guardrail` — what NOT to say
- `Persona` — how to say it (tone, terminology)
- `Vault` — domain-specific knowledge package

## 3. LLM as glue (NOT a fourth axis)

LLM connects axes; never holds state.

- Identity context + Knowledge → Interaction draft
- Interaction message + Knowledge → Identity activity (intent detection)
- Identity record + Knowledge → Interaction safety check

State lives in axes. LLM is stateless per-call.

## 4. Overview layer

Read-only aggregator across the three axes. Single entry point for staff.
Click anything → drill down to the specific axis.

Not editable. Just a window.

## 5. Meta-operations layer

System administration invisible to desk users:
- LLM token usage / cost tracking
- Database backups
- Channel API quota monitoring
- Security incident response
- System updates / migrations

Should never appear in the daily user's interface.

## 6. Technology stack

```
Language:    Elixir 1.17+ on OTP 27+
Framework:   Phoenix 1.7+ with LiveView 0.20+
Domain:      Ash Framework 3.0+
  - ash_postgres       (data layer)
  - ash_phoenix        (LiveView form integration)
  - ash_authentication (auth)
  - ash_oban           (background jobs)
  - ash_paper_trail    (audit)
  - ash_graphql        (API, when needed)
  - ash_admin          (admin UI)
  - ash_ai             (MCP integration, experimental)
Database:    PostgreSQL 16
  - pgvector           (embeddings, RAG)
  - pg_trgm            (fuzzy + non-ASCII text search)
Background:  Oban (job queue)
Realtime:    Phoenix.PubSub
AI:          Anthropic API direct via Req (NO Python service)
Frontend:    Phoenix LiveView only (NO React/Vue/Svelte)
```

## 7. Module layout

```
lib/ashy_walnut_desk/
├── application.ex
├── accounts/                  # User, Role, Token (AshAuthentication)
├── identity/                  # Identity-axis resources
├── interaction/               # Conversation, Message, Channel, Draft
│   └── adapters/              # ChannelAdapter implementations (deployer-defined)
├── knowledge/                 # Manual, Guardrail, Persona, Vault
├── ai/                        # AnthropicClient, PromptBuilder
├── safety/                    # Validator, PIIRedactor
├── audit/                     # via AshPaperTrail
└── workers/                   # Oban workers

lib/ashy_walnut_desk_web/
├── endpoint.ex
├── router.ex
├── controllers/
│   └── webhooks/              # per-channel webhook endpoints
├── live/
│   ├── overview_live/         # Overview (read-only aggregator)
│   ├── identity_live/         # Identity-axis views
│   ├── inbox_live/            # Interaction views
│   ├── knowledge_live/        # Knowledge views
│   └── components/            # CountdownSendButton, ...
└── components/                # Shared LiveComponents
```

## 8. Data invariants

1. Every `Identity` record has a SHA-256 hash of its primary identifier (raw identifier never stored).
2. Every `Message` belongs to exactly one `Conversation`.
3. Every `Conversation` belongs to exactly one `Channel` and one `Identity`.
4. Every outbound `Message` has a non-null `approved_by` (User).
5. Every outbound `Message` has at least 5 seconds between draft creation
   and actual send (5-second countdown enforced).
6. Every `Draft` has an audit trail (prompt, model, response, validator output).
7. Every sensitive-record-touching Resource has `AshPaperTrail` enabled.
8. `Manual`, `Guardrail`, `Persona` are versioned (not hard-deleted).

## 9. External integrations

### LLM provider (Phase 4+)

- Direct HTTP via Req library (no Python intermediary — see ADR-004)
- Prompt caching where the provider supports it (system prompt + Persona + Manual)
- Streaming for responsive UI
- One provider abstracted via `AI.Client` behaviour; deployer can swap providers

### Channel adapters (Phase 3+)

The framework defines a `Channel.Adapter` behaviour. Each deployment
picks the channels relevant to its domain and implements (or installs)
adapters for them. Common adapter responsibilities:

- Inbound: webhook → signature verify → adapter → Conversation + Message
- Outbound: Draft → human approval → countdown → Oban worker → API call → retry on fail
- Channel-specific policy enforcement (e.g., service-window rules, template
  pre-approval, rate limits) lives in the adapter, not in core code

The framework ships zero channel adapters. Deployers add them per ADR-006.

## 10. Failure modes & graceful degradation

| Failure | Degradation |
|---|---|
| LLM API down | Drafts pause; manual entry still works |
| Channel API down | Outbound queues in Oban; inbound buffers in webhook |
| Postgres down | App stops serving; alert via meta-ops |
| pgvector index corrupt | Fallback to pg_trgm full-text search |
| Guardrail triggered | Block send, alert operator, never bypass |
| Identity match ambiguous | Require manual matching, no auto-link |

## 11. Security posture

- All endpoints authenticated (AshAuthentication)
- All actions authorized (Ash policies)
- All sensitive records audited (AshPaperTrail)
- Sensitive identifiers (phone, email, etc.) hashed (SHA-256 with salt) before storage
- Names and other PII stored as `sensitive? true`
- Secrets via env vars (never in repo)
- Webhook signatures verified (per-adapter)
- TLS termination at the deployment's edge (Cloudflare Tunnel is the easy path)
- Internal services bound to localhost only

## 12. Testing strategy

- **Unit**: Ash actions, validators, prompt builders
- **Integration**: LiveView flows (Phoenix.LiveViewTest)
- **Property-based**: invariants (StreamData)
- **Manual**: AI output quality, tone fidelity
- **No real customer data in tests** (use fakers with fake data)

## 13. Open architectural questions

(Updated per phase retrospective.)

- [ ] Multi-tenant: per-deployment schema or shared with tenant_id? (decide Phase 5 end)
- [ ] Real-time AI streaming via LiveView: technical feasibility study needed (Phase 4)
- [ ] Persona versioning: full snapshots or diffs? (Phase 5)
