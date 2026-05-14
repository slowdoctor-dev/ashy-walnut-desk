# Story 1.6: Identity LiveViews + timeline UI

**Phase**: 1
**Estimate**: 3h
**Depends on**: 1.2, 1.3, 1.4, 1.5
**Status**: done

---

## Goal

Implement Identity LiveView pages and timeline rendering so operators/viewers can observe linked records and role-based UI behavior.

## Context

Resource-level correctness is insufficient without observable operator UX. This story delivers the primary Identity UI contract in Phase 1.

## Reference specs

- `/AGENTS.md` §6 (LiveView layout and standards)
- `/specs/phase-1/requirements.md` §2 (AC7, AC10, AC11, AC13)
- `/specs/phase-1/architecture.md` §4 (IdentityLive components)

## Acceptance criteria

- [x] AC1: `IdentityLive.Index` and `IdentityLive.Show` routes render for authenticated actors and list non-archived identities by default. — Verify: `mix test test/ashy_walnut_desk_web/live/identity_live/index_test.exs`
- [x] AC2: Timeline view shows linked Event/Appointment/Note records chronologically for an identity. — Verify: `mix test test/ashy_walnut_desk_web/live/identity_live/show_test.exs`
- [x] AC3: `:viewer` sees timeline/read surfaces but cannot trigger write actions from UI paths; write attempts fail at action boundary. — Verify: `mix test test/ashy_walnut_desk_web/live/identity_live/show_test.exs`
- [x] AC4: Archive/recover UX behavior is consistent with soft-delete policy (admin recover only, archived hidden from default index). — Verify: `mix test test/ashy_walnut_desk_web/live/identity_live/index_test.exs`

## Files to create

```
lib/ashy_walnut_desk_web/live/identity_live/index.ex   — identity list
lib/ashy_walnut_desk_web/live/identity_live/show.ex   — identity detail + timeline
lib/ashy_walnut_desk_web/live/identity_live/new.ex   — create identity form
lib/ashy_walnut_desk_web/live/identity_live/edit.ex   — edit identity form
lib/ashy_walnut_desk_web/live/identity_live/timeline_component.ex   — timeline renderer
test/ashy_walnut_desk_web/live/identity_live/index_test.exs   — index behavior tests
test/ashy_walnut_desk_web/live/identity_live/show_test.exs   — timeline + role behavior tests
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex   — Identity LiveView routes
lib/ashy_walnut_desk_web/live_user_auth.ex   — on_mount usage as needed
```

## Implementation notes

Keep forms/action wiring inside existing auth live session behavior; do not introduce separate API endpoints.

## Safety review

- Sensitive records touched? Yes — identity details and timeline content.
- AI output to end user possible? No.
- Guardrails applied? Role-based read/write policy boundaries.
- Audit trail covered? Indirectly via resource actions already audited.

## Out of scope (will NOT do in this story)

- Property-based ordering invariants: deferred to 1.7
- Playwright screenshot capture: deferred to 1.9

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/live/identity_live/index_test.exs
mix test test/ashy_walnut_desk_web/live/identity_live/show_test.exs
```

## Notes during implementation

- Decisions made:
  - Show LiveView embeds three named inline forms (event_form / appointment_form / note_form)
    — using distinct `as:` values per form so DOM ids stay unique within a single LV
    (otherwise Event `body` and Note `body` collide on `id="form_body"`).
  - Submit handlers re-inject `identity_id` into form params before
    `AshPhoenix.Form.submit/2`, because `submit` re-validates with the new params
    and would drop the constructor-time `identity_id` otherwise.
  - Test login helper signs in via magic-link then immediately calls `:assign_role`
    (authorize?: false) to restore the test-intended role, since
    `sign_in_with_magic_link` runs `AssignFirstUserAdmin` which overrides role.
  - Admin viewing an archived identity falls back to the `:read_with_archived`
    action; non-admin can't reach the Show page for archived rows by design.
- Spec drift noticed: none.
- Gotchas to add to AGENTS.md §10:
  - `AshPhoenix.Form.submit/2` re-validates with the params you pass, replacing
    constructor-time params. Constant attributes (parent FKs) must be re-injected
    into the submit params or the validation drops them.
  - When two `AshPhoenix.Form`s on the same LV expose fields with the same name
    (e.g. `body`), pass distinct `as:` values per form so the rendered `id`
    attributes don't collide. LiveView raises `Duplicate id found` otherwise.
