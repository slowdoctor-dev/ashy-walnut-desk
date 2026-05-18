# ADR-024: Inbound intake policy — system actor + provisional Identity + 7-day dedupe

**Status**: Accepted
**Date**: 2026-05-18
**Deciders**: solo maintainer

---

## Context

Phase 2 sealed the chain entry: `Inbox.:record_inbox` requires an
operator/admin actor + relates `recorded_by` via `relate_actor/1`
+ has `recorded_by_id` marked `attribute_writable?: false` (PR
#37 R2-1 fix). The Inbox is the chain entry point.

Phase 3 introduces inbound: a Twilio webhook arrives at 2am from a
random phone number. No operator actor exists in that request
context. The webhook handler still needs to create chain rows
(Identity, Conversation, Inbox, Message) to make the inbound
visible to the operator on next LV mount.

The architect needs to pick:
1. Who is the actor on inbound-created chain rows?
2. What happens when the inbound `From` matches no existing
   Identity?
3. What happens when Twilio retries the same `MessageSid`?

## Options considered

### Q1 — Actor on inbound chain rows

#### A1: Synthetic system actor

A singleton `User` row (`role: :system`,
`email: "system+inbound@<phx_host>"`) created at app boot. The
webhook handler authenticates as this actor for the duration of
the intake transaction. The system actor is locked down — cannot
sign in via magic link; cannot invoke send-path actions (asserted
by a test).

- Pros: keeps the existing `relate_actor(:recorded_by)` shape;
  audit events have a non-null `actor_id` (the system actor's
  UUID); paper trail correctly attributes inbound rows.
- Cons: introduces a real `User` row that doesn't represent a
  human; risk that a future bug treats the system actor as a
  privileged operator. Mitigated by the lockdown test.

#### A2: Nullable `recorded_by_id` + new internal action

Add a separate `Inbox.:record_inbound` action with
`recorded_by_id` allowed to be nil. Same approach for `Message`
and `AuditEvent`.

- Pros: no synthetic User row.
- Cons: `recorded_by_id`'s `attribute_writable?: false` + `allow_nil?: false`
  invariant breaks; the recorded_by relationship semantic ("who
  recorded this") no longer holds for inbound rows. Paper trail
  starts logging nil actors.

#### A3: Hybrid — system actor for internal-only actions, nil for everything else

Same as A1 but only the internal `:record_inbound` /
`:record_message :inbound` rows carry the system actor; admin
viewers see "auto-recorded by system" in the UI.

- Pros: invariants stay intact for operator-initiated paths.
- Cons: same as A1 with more LV display logic.

### Q2 — Unknown identifier handling (Q5 from requirements)

#### B1: Always create provisional Identity

Webhook intake creates an Identity row when `From` doesn't match.
Mark it `provisional?: true` so operator UI can show "this
identity was auto-created from inbound."

- Pros: operator can immediately see the inbound; promotion to a
  confirmed Identity is a one-click operation.
- Cons: a spammer pinging random `From` numbers creates a flood
  of provisional Identity rows. Mitigated by the webhook rate
  limiter + signature verification (only authenticated Twilio
  traffic reaches intake).

#### B2: Hold all unknowns in a triage queue

Don't create Identity; record the inbound in a separate
`IntakeQueue` resource. Operator triages each one manually.

- Pros: no Identity-table pollution.
- Cons: operator workflow becomes "wake up → 47 triage rows" for
  every campaign. Worse UX than B1; the provisional flag already
  gives operators a signal.

#### B3: Reject all unknowns

Drop the inbound; record only in `InboundDelivery.outcome:
:failed_intake`.

- Pros: simplest.
- Cons: hostile to deployers in a "support inbox" mode where
  most inbounds will be from unknown senders. Real-world
  deployer pain.

### Q3 — Retry dedupe contract (Q4 from requirements)

#### C1: Dedupe by Twilio's `MessageSid` with 7-day retention

New `InboundDelivery` Ash resource with unique index on `(provider,
provider_message_id)`. Retain rows for 7 days via daily AshOban
trigger.

- Pros: leverages Twilio's own delivery ID; trivial uniqueness
  enforcement; small dedupe window matches operational reality
  (Twilio retries rare beyond 24h).
- Cons: deletion after 7 days means an extremely-late Twilio
  retry would re-process. Acceptable per the rarity.

#### C2: Compute hash from body + From + To + sent_at, store forever

Same dedupe but use a content hash, retained indefinitely.

- Pros: works across providers; forever-retention is conceptually
  simple.
- Cons: hashes are larger than UUIDs; storage grows monotonically
  (Phase 0's TO-3 token-expunge pattern exists exactly to avoid
  this).

#### C3: No dedupe — rely on Twilio's at-least-once semantics

Let duplicate inbounds create duplicate chain rows. Operator
ignores the dup.

- Pros: no new resource.
- Cons: duplicate Inbox rows make the operator chase ghost work;
  duplicate Message rows pollute history.

## Decision

We chose: **A1 + B1 + C1.**

- **A1 system actor** — singleton User row, locked down to
  inbound-only actions via context-flag policies.
- **B1 provisional Identity** — unknown inbound creates a
  provisional Identity with a deterministic masked display name;
  operator promotes via existing `:edit` action.
- **C1 dedupe by MessageSid, 7-day retention** — `InboundDelivery`
  resource with daily AshOban expunge trigger.

Reasoning:

- A1 keeps the existing `recorded_by` invariants intact across the
  entire codebase. The synthetic actor is a one-row addition with
  a clear scope (asserted by a test). Mitigation against bugs
  treating system actor as privileged: the test asserts the system
  actor cannot drive `Draft.:approve`, `Action.:execute`,
  `Compensation.:trigger`, or any send-path action.
- B1 matches operator workflow expectations: real-time inbound is
  visible immediately; the `provisional?` flag is a clear "needs
  attention" signal in the LV.
- C1 piggybacks on Twilio's own delivery ID + the existing
  Token-expunge pattern. 7-day retention is generous given
  Twilio's typical retry behavior (most retries within minutes).

## Consequences

### Positive

- Single new `User` row + single new `Identity.provisional?` flag +
  single new `Interaction.InboundDelivery` resource. Three additive
  changes, no invariant rewrites.
- Webhook intake transaction is small (record_delivery →
  resolve_identity → resolve_conversation → record_inbox →
  record_message) and idempotent on Twilio retry via the unique
  index.
- Operator UI gets clear signals: provisional Identity rows,
  failed-intake `InboundDelivery` rows for ambiguity, the
  AuditLive.Chain viewer for hash continuity.

### Negative / accepted trade-offs

- The system actor row is mildly weird — it appears in the User
  table but represents no human. Mitigation: locked-down policy
  + test. The naming pattern (`system+inbound@<host>`) makes the
  intent obvious.
- Provisional Identity rows accumulate over time. Mitigation:
  operator should periodically promote (`:edit`) or archive
  (`:archive`) them; an admin LV view of provisionals (separate
  from the main Identities list) might land in Phase 4+ if the
  list grows noisy.
- 7-day dedupe means a Twilio retry beyond 7 days would re-
  process. Acceptable; Twilio's retry envelope is much shorter.

### Follow-up actions

- [x] `Accounts.ensure_system_actor/0` called at app boot via
      `Application.start/2` hook
- [x] `Checks.FromInboundWebhook` policy check
- [x] `Inbox.:record_inbound` internal action with new check
- [x] `Identity.:register_provisional` internal action
- [x] `Identity.provisional?` boolean + `discovered_via` atom
      attributes
- [x] `Interaction.InboundDelivery` resource (immutable) with
      `(provider, provider_message_id)` unique index
- [x] Daily AshOban trigger expunging 7-day-old `InboundDelivery`
      rows
- [x] System-actor lockdown test (cannot drive send-path actions)
- [x] `RegistrationGate` extended to reject `system+%` email
      patterns from magic-link sign-in
- [x] `Identity.provisional_display_name/1` helper with US +
      generic-phone + non-phone (Phase 6+) format branches

## References

- Related ADRs: ADR-016 (Four-stage record chain), ADR-019
  (Soft-delete default), ADR-022 (Twilio as first real adapter),
  ADR-023 (Oban for outbound retry)
- Phase 2 PR #37 (R2-1) — the
  `recorded_by_id`/`attribute_writable?: false` lockdown that
  this ADR works around for inbound
- Phase 3 requirements: `specs/phase-3/requirements.md` AC #16-19
- Phase 3 architecture: `specs/phase-3/architecture.md §3, §5.2, §12 Q4-Q5`
