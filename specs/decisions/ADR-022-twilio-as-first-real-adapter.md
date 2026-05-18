# ADR-022: Twilio SMS as the first real channel adapter

**Status**: Accepted
**Date**: 2026-05-18
**Deciders**: solo maintainer

---

## Context

Phase 2 shipped the four-stage record chain (Inbox → Draft → Action →
Compensation) with a stub adapter that returns `{:ok, %{stub: true}}`
without external I/O. Phase 3's analyst draft locks the first real
adapter as a phase-entry decision (`specs/phase-3/requirements.md`
AC #2, open question Q1).

Candidate channels: SMS, WhatsApp Business, Line, KakaoTalk, etc.
The framework needs **one concrete provider** to validate the
chain under real external network conditions while keeping the
adapter framework extensible for future providers.

## Options considered

### Option 1: SMS via Twilio

- **Pros**: cleanest provider API (REST + form-encoded webhooks);
  least geographically scoped (every market has SMS, with regional
  pricing differences); idempotency-key + signature verification
  are well-documented; sandbox account is free + instantly
  provisioned; the protocol shape (request/response, signed
  webhook, idempotency-key) is the most common across the other
  candidates so the contract generalizes.
- **Cons**: A2P 10DLC registration in the US adds deployer
  friction; per-message cost (~$0.0079/SMS) means a buggy retry
  loop is real money; SMS body length is 160 chars (or 70 for
  unicode), forcing message-segment thinking.

### Option 2: WhatsApp Business Cloud API (Meta)

- **Pros**: free-tier conversations; rich media + templates
  natively; widely used in Brazil/India/SEA.
- **Cons**: template pre-approval gauntlet (24h+ review per
  message template); strict 24-hour reply window after
  customer-initiated message; Meta-app gating; webhook payload
  format is more complex (JSON, multiple message types).
- Verdict: high upfront friction for framework validation work.

### Option 3: KakaoTalk Bizmessage

- **Pros**: dominant channel in Korean market; first deployer
  context may be Korea.
- **Cons**: requires Korean business registration (사업자등록증);
  template approval through KakaoBizCenter; documentation
  primarily Korean; smaller community for Elixir-side integration
  patterns.

### Option 4: Line Messaging API

- **Pros**: free tier; widely used in Japan/Taiwan/Thailand.
- **Cons**: requires Line Business Account approval; channel
  access tokens with their own rotation cadence; similar locality
  to KakaoTalk for framework-validation purposes.

### Option 5: Ship all four

- **Pros**: maximal deployer optionality from day one.
- **Cons**: 4× scope (~150-250h instead of ~50h); violates the
  seasoned-hand SDD discipline of "one phase = one working-system
  increment"; the chain-mechanics-meets-real-network learning gets
  buried.

## Decision

We chose **Option 1: SMS via Twilio**, *with the adapter framework
hardened so options 2–4 land as ~1 story each in Phase 6+*.

Reasoning:

- The framework needs *one concrete provider* to drive real-network
  failure modes through the chain. Twilio's protocol shape (REST +
  signed webhook + idempotency-key) is the most generalizable to
  the other candidates.
- The first deployer's choice may be any of the four; locking the
  framework to Twilio doesn't preclude later deployers picking
  KakaoTalk or WhatsApp because the `Interaction.Adapter` behaviour
  is the only extension point (enforced by an adapter-contract
  conformance test running Twilio + a synthetic `Adapters.Echo`
  fixture).
- Twilio's developer ergonomics (free sandbox, fast credential
  provisioning, comprehensive docs) keep framework validation
  cycles short.

## Consequences

### Positive

- Real chain validation against external network failure modes
  (transient 5xx, rate limits, signature mismatches) before any
  future provider lands.
- Adapter contract gets a real second implementation
  (`Adapters.Echo`) — the conformance test isn't a single-impl
  tautology.
- Deployers in US/EU/most-everywhere can use the shipped adapter
  directly. Deployers in JP/KR/SEA add their adapter post-Phase 3
  via the documented extension point.

### Negative / accepted trade-offs

- US A2P 10DLC registration is a real deployer-side friction.
  Mitigation: framework surfaces Twilio's `30007` error with a
  hint pointing at the 10DLC docs (per Phase 3 architecture §12
  Q2).
- Per-message cost means terminal-failure retry budgets matter.
  Phase 3 caps at 5 attempts (~3h) per Q3 decision.
- The framework's stub channel (slug `"stub"`) continues to exist
  for development; deployers replace it with `"twilio-sms"` per
  their deployer-instance seed task.

### Follow-up actions

- [x] `Adapters.Twilio` lives at `lib/ashy_walnut_desk/interaction/adapters/twilio.ex`
- [x] `Adapters.Echo` lives at `lib/ashy_walnut_desk/interaction/adapters/echo.ex` (test-only)
- [x] Adapter-contract conformance test runs both implementations
- [x] `config/runtime.exs` reads `TWILIO_ACCOUNT_SID`,
      `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` from env in prod
      block; fails-fast if missing
- [x] `mix phase3.webhook.preflight` validates Twilio config + the
      `Channel{slug: "twilio-sms"}` row exists

## References

- Related ADRs: ADR-004 (Anthropic direct), ADR-006 (Domain as
  config), ADR-010 (Deployment as private repo), ADR-016
  (Four-stage record chain)
- External: https://www.twilio.com/docs/sms/quickstart/elixir
- Phase 3 requirements: `specs/phase-3/requirements.md`
- Phase 3 architecture: `specs/phase-3/architecture.md`
