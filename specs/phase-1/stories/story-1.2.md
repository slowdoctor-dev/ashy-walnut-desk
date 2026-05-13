# Story 1.2: Identity resource + hashing + soft-delete base pattern

**Phase**: 1
**Estimate**: 3h
**Depends on**: 1.1
**Status**: done

---

## Goal

Implement the `Identity` resource with hashed primary identifier, redacted audit/version behavior, and reusable soft-delete change pattern used by later Identity-axis resources.

## Context

Phase requirements hinge on Identity as the owner context and on the invariant that raw primary identifiers are never stored. This story also establishes the shared soft-delete change module that later resource stories depend on.

## Reference specs

- `/AGENTS.md` §7.3–§7.4 (audit mandatory, sensitive-data handling)
- `/specs/phase-1/requirements.md` §2 (AC4, AC5, AC10)
- `/specs/phase-1/architecture.md` §3.1 (`Identity`) and §2 (shared `SoftDelete` + `HashPrimaryIdentifier` changes)
- `/specs/decisions/ADR-019-soft-delete-axis-records.md`

## Acceptance criteria

- [x] AC1: `Identity` resource exists with required action surface (`register_identity`, `update_profile`, `archive`, `recover`, default read vs archived read) and policy boundaries for `admin`/`operator`/`viewer`. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [x] AC2: raw primary identifier input is accepted only as action input and persisted only as hash; plaintext is not stored on the resource. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [x] AC3: shared `Identity.Changes.SoftDelete` module is introduced and used by `Identity.archive`; archived rows are excluded by default reads and restorable by admin recover action. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [x] AC4: Identity paper-trail/version rows redact sensitive attributes and Version reads are admin-only. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`

## Files to create

```
lib/ashy_walnut_desk/identity/identity.ex   — Identity resource
lib/ashy_walnut_desk/identity/changes/hash_primary_identifier.ex   — hashing change
lib/ashy_walnut_desk/identity/changes/soft_delete.ex   — shared soft-delete change
lib/ashy_walnut_desk/identity/identity/version_policies.ex   — Version policy mixin
test/ashy_walnut_desk/identity/identity_test.exs   — Identity unit tests
```

## Files to modify

```
lib/ashy_walnut_desk/identity.ex   — register Identity resource
priv/repo/migrations/*   — generated migration(s)
priv/repo/resource_snapshots/*   — generated snapshots
```

## Implementation notes

This story establishes the reusable soft-delete + version-policy pattern. Later resources should reuse it rather than redefining policy/redaction conventions.

## Safety review

- Sensitive records touched? Yes — customer identity and hashed identifier.
- AI output to end user possible? No.
- Guardrails applied? Ash policies + sensitive attribute handling.
- Audit trail covered? Yes — Identity paper trail + Version access control.

## Out of scope (will NOT do in this story)

- Event/Appointment/Note resources: deferred to 1.3–1.5
- Timeline UI behavior: deferred to 1.6
- Property-based invariants: deferred to 1.7

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/identity/identity_test.exs
```

## Notes during implementation

- Decisions made:
  - Primary read action filters `is_nil(deleted_at)`; `primary_read_warning?: false` is set on `use Ash.Resource` to silence the Ash 3.x verifier that flags filtered primary reads as suspicious. The escape hatch is the explicit `read_with_archived` action, admin-gated.
  - `register_identity` accepts a write-only `:primary_identifier` argument (sensitive, `allow_nil?: false`); `HashPrimaryIdentifier` reads it from the changeset and `force_change_attribute/3` stores only the salted SHA-256. `update_profile` deliberately does **not** accept the identifier — re-hash semantics deferred until a story asks for them.
  - `archive` and `recover` use `require_atomic?(false)` because the `SoftDelete` change inspects the current `deleted_at` to be idempotent. The architecture spec wants both behaviors and atomic mode rejects custom changes.
  - `created_by_id` is set via `change relate_actor(:created_by)` and the `belongs_to` is `allow_nil?: false`, so a missing actor on `register_identity` produces a clean error rather than orphaning the row.
- Spec drift noticed:
  - None. Resource shape matches architecture §3.1 exactly. The migration includes neither the `(identity_id, deleted_at)` index nor `ON DELETE RESTRICT` from architecture §7.3–7.4 — those land with the child resources (Event/Appointment/Note) that actually have an `identity_id` FK in stories 1.3–1.5.
- Gotchas to add to AGENTS.md §10:
  - Added (this commit): "Test fixtures that `TRUNCATE` a parent table referenced by other tables' FKs must use `TRUNCATE … CASCADE`." Two pre-existing tests (`first_user_race_test.exs`, `assign_first_user_admin_test.exs`) broke because `identities.created_by_id` now references `users.id`; they were updated to use `CASCADE` rather than enumerate every future FK referrer.
