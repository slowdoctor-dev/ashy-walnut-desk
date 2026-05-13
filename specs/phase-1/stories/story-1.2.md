# Story 1.2: Identity resource + hashing + soft-delete base pattern

**Phase**: 1
**Estimate**: 3h
**Depends on**: 1.1
**Status**: ready

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

- [ ] AC1: `Identity` resource exists with required action surface (`register_identity`, `update_profile`, `archive`, `recover`, default read vs archived read) and policy boundaries for `admin`/`operator`/`viewer`. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [ ] AC2: raw primary identifier input is accepted only as action input and persisted only as hash; plaintext is not stored on the resource. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [ ] AC3: shared `Identity.Changes.SoftDelete` module is introduced and used by `Identity.archive`; archived rows are excluded by default reads and restorable by admin recover action. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`
- [ ] AC4: Identity paper-trail/version rows redact sensitive attributes and Version reads are admin-only. — Verify: `mix test test/ashy_walnut_desk/identity/identity_test.exs`

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
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
