# Story 1.3: Event resource linked to Identity

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2
**Status**: ready

---

## Goal

Add the `Event` resource as the primary "what happened" record linked to Identity, with role-based read/write policies and soft-delete/audit behavior.

## Context

Events are the first chronological child record in the Identity timeline and are required before follow-up appointments can reference an originating event.

## Reference specs

- `/AGENTS.md` §6 (action naming and policy requirements)
- `/specs/phase-1/requirements.md` §2 (AC2, AC3, AC7, AC8, AC9, AC10)
- `/specs/phase-1/architecture.md` §3.2 (`Event`)

## Acceptance criteria

- [ ] AC1: `Event` resource exists with `record_event`, update, archive, recover, and filtered read behavior, all linked to owning Identity. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`
- [ ] AC2: Event policies enforce viewer read-only and deny unauthenticated access to non-public actions. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`
- [ ] AC3: Event changes are auditable with redacted sensitive payloads and admin-only Version reads. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`

## Files to create

```
lib/ashy_walnut_desk/identity/event.ex   — Event resource
lib/ashy_walnut_desk/identity/event/version_policies.ex   — Version policy mixin
test/ashy_walnut_desk/identity/event_test.exs   — Event unit tests
```

## Files to modify

```
lib/ashy_walnut_desk/identity.ex   — register Event resource
priv/repo/migrations/*   — generated migration(s)
priv/repo/resource_snapshots/*   — generated snapshots
```

## Implementation notes

Reuse the soft-delete and version-policy conventions introduced in 1.2.

## Safety review

- Sensitive records touched? Yes — event summary/body linked to customer identity.
- AI output to end user possible? No.
- Guardrails applied? Ash policies + redaction.
- Audit trail covered? Yes — Event paper trail.

## Out of scope (will NOT do in this story)

- Appointment follow-up validation: deferred to 1.4
- Timeline UI and merged ordering: deferred to 1.6/1.7

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/identity/event_test.exs
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
