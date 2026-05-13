# Story 1.3: Event resource linked to Identity

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.2
**Status**: done

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

- [x] AC1: `Event` resource exists with `record_event`, update, archive, recover, and filtered read behavior, all linked to owning Identity. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`
- [x] AC2: Event policies enforce viewer read-only and deny unauthenticated access to non-public actions. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`
- [x] AC3: Event changes are auditable with redacted sensitive payloads and admin-only Version reads. — Verify: `mix test test/ashy_walnut_desk/identity/event_test.exs`

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
  - Added a composite `(identity_id, deleted_at)` index and `on_delete: :restrict` on the FK to `identities` at resource definition time (arch §7.3, §7.4), so the generated migration carries them.
  - Mirrored 1.2's `read_with_archived` admin-only read on Event for parity with `Identity`; arch §3.2 lists only `read` explicitly, but `read_with_archived` is the documented project pattern (see §3.1) and the timeline/admin-recovery flows need it. Treated as convention, not drift.
  - Unauthenticated `record_event` is refused with `Ash.Error.Invalid` (from `relate_actor` finding no actor) rather than `Forbidden`; the test accepts either since both satisfy AC2 ("deny unauthenticated access").
- Spec drift noticed: none.
- Gotchas to add to AGENTS.md §10: none new (existing relate_actor + nil-actor interaction is already implicit in Ash semantics; documented inline in the test).
