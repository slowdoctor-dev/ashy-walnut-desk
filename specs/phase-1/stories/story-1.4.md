# Story 1.4: Appointment resource with follow-up validation

**Phase**: 1
**Estimate**: 3h
**Depends on**: 1.2, 1.3
**Status**: ready

---

## Goal

Implement the `Appointment` resource (including follow-ups via enum type) and enforce the `originating_event_id` validation contract.

## Context

Phase 1 uses one Appointment resource for initial/follow-up/recurring records. The follow-up constraint is a core domain invariant and must be unit-test verified in this story.

## Reference specs

- `/AGENTS.md` §6 (intent verbs, policy requirements)
- `/specs/phase-1/requirements.md` §2 (AC6, AC8, AC12)
- `/specs/phase-1/architecture.md` §3.3 (`Appointment`)

## Acceptance criteria

- [ ] AC1: `Appointment` resource exists with `appointment_type`, `scheduled_for`, status transitions (`schedule_appointment`, `reschedule`, `cancel`, `complete`), and Identity ownership link. — Verify: `mix test test/ashy_walnut_desk/identity/appointment_test.exs`
- [ ] AC2: Validation enforces `originating_event_id` semantics for follow-up appointments (`required when type is :follow_up`; otherwise nil). — Verify: `mix test test/ashy_walnut_desk/identity/appointment_test.exs`
- [ ] AC3: Appointment write policies deny `:viewer` and unauthenticated actors; read is allowed to `:viewer`. — Verify: `mix test test/ashy_walnut_desk/identity/appointment_test.exs`
- [ ] AC4: Appointment supports soft-delete/recover and redacted audited versions with admin-only Version reads. — Verify: `mix test test/ashy_walnut_desk/identity/appointment_test.exs`

## Files to create

```
lib/ashy_walnut_desk/identity/appointment.ex   — Appointment resource
lib/ashy_walnut_desk/identity/appointment/version_policies.ex   — Version policy mixin
test/ashy_walnut_desk/identity/appointment_test.exs   — Appointment unit tests
```

## Files to modify

```
lib/ashy_walnut_desk/identity.ex   — register Appointment resource
priv/repo/migrations/*   — generated migration(s)
priv/repo/resource_snapshots/*   — generated snapshots
```

## Implementation notes

Keep this story record-only; reminder/notification behavior remains deferred per phase scope.

## Safety review

- Sensitive records touched? Yes — scheduled customer-facing records and linked context.
- AI output to end user possible? No.
- Guardrails applied? Policy + validation constraints.
- Audit trail covered? Yes — Appointment paper trail.

## Out of scope (will NOT do in this story)

- Reminder/send pipeline: deferred to Phase 4
- Timeline rendering: deferred to 1.6

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/identity/appointment_test.exs
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
