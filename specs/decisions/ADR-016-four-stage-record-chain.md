# ADR-016: Four-Stage Record Chain for Communications

**Status**: Accepted
**Date**: 2026-05
**Deciders**: maintainer

---

## Context

Every outbound message in a regulated-service communication system must:

- Be traceable from arrival to send
- Allow human review at the right moment
- Support remediation when something goes wrong (since channels rarely
  support actual "unsend")
- Survive audit scrutiny

Several patterns were considered: simple send-with-log (insufficient
audit), state-machine on a single Message record (audit-poor), and the
four-stage record chain.

## Decision

Adopt a **four-stage record chain** as the canonical lifecycle for every
outbound communication:

```
Inbox        — incoming intent (customer message, scheduled action, or operator-initiated)
   ↓ status: open → drafting
Draft        — proposed reply (AI-generated or human-composed)
   ↓ status: drafting → approved
Action       — the actual send
   ↓ status: pending → executed | failed
Compensation — registered remediation, executable later if needed
   ↓ status: registered → completed (only if invoked)
```

Each transition emits an immutable `AuditEvent`. Events are hash-chained
(each event's hash includes the previous event's hash) to make tampering
detectable.

### Why all four stages always

The Compensation record is always created when the Action executes, even
if it is never invoked. This is a design discipline: at the time of
sending, we are forced to ask "what would remediation look like?" and
record it. Later remediation is then a confirmation, not an improvisation.

### "Honest framing" principle

When a Compensation is invoked, the UI MUST state that the original
message was not unsent — a remediation message was sent. Real channels
do not support unsend; pretending otherwise misleads the operator and
the customer.

## Status enums

```
Inbox.status        :: :open | :drafting | :executed | :dismissed
Draft.status        :: :drafting | :approved | :superseded | :rejected
Action.status       :: :pending | :executed | :failed | :rolled_back
Compensation.status :: :registered | :triggered | :completed | :failed
```

## Consequences

### Positive
- Every outbound communication has the same lifecycle shape
- Audit chain integrity verifiable via single command
- Remediation is planned, not improvised
- Pattern transfers across channels (email, messaging, SMS, etc.)

### Negative / accepted trade-offs
- Four records per communication instead of one
- Operator UI must show all four stages clearly
- Compensation content must be authored at draft-approval time

### Follow-up
- AuditEvent verification tool implementation
- Default Compensation templates per channel adapter
- LiveView component for the full chain visualization

## References

- ADR-005 (human approval required)
- ADR-013 (5-second countdown)
- AGENTS.md §7 (Safety Rules — INVIOLABLE)
