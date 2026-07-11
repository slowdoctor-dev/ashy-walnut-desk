# Story 5.6: Manual admin LiveView + generation-panel retrieval badge

**Phase**: 5
**Estimate**: 3h
**Depends on**: 5.1, 5.5
**Status**: done

---

## Goal

Give admins a Manual authoring surface (`/manuals`) and operators a
per-candidate retrieval provenance badge in the generation panel — all
strings gettext-backed.

## Context

The human-facing slice: authoring UX for 5.1 content and transparency
for 5.5 provenance (resolved question Q5: operators see count+mode).

## Reference specs

- `/specs/phase-5/architecture.md` §6 (LiveView components)
- `/AGENTS.md` §6 (gettext, layout), §10 gotchas (duplicate form ids, `:if` booleans)

## Acceptance criteria

- [x] AC1: `/manuals` (admin-only live_session) lists manuals with title/slug/status/revision + embedded-state, supports archive/restore; operators and viewers are denied at mount. — Verify: `mix test test/ashy_walnut_desk_web/live/manual_live/index_test.exs`
- [x] AC2: `/manuals/new` + `/manuals/:id/edit` drive `:author`/`:revise` via `AshPhoenix.Form` (distinct `as:` names), show validation errors, and display paper-trail version history read-only. — Verify: `mix test test/ashy_walnut_desk_web/live/manual_live/form_test.exs`
- [x] AC3: Generation panel candidates render `data-role="retrieval-badge"` with mode + excerpt count from `ai_retrieval` (`knowledge: 3 excerpts (vector)` / `knowledge: none`); badge absent for pre-Phase-5 drafts (nil `ai_retrieval`). — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/retrieval_badge_test.exs`
- [x] AC4: Every new user-facing string goes through gettext; `mix gettext.extract` produces no drift. — Verify: `mix gettext.extract && git diff --exit-code priv/gettext/`

## Files to create

```
lib/ashy_walnut_desk_web/live/manual_live/index.ex
lib/ashy_walnut_desk_web/live/manual_live/form.ex
test/ashy_walnut_desk_web/live/manual_live/index_test.exs
test/ashy_walnut_desk_web/live/manual_live/form_test.exs
test/ashy_walnut_desk_web/live/inbox_live/retrieval_badge_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                                — /manuals routes (admin session)
lib/ashy_walnut_desk_web/live/inbox_live/generation_panel.ex      — badge
priv/gettext/*                                                    — extracted strings
```

## Implementation notes

Mount/auth pattern: clone the `/audit/chain` admin live_session
(ADR-020 cookie on_mount). Remember LiveView `mount/3` runs twice —
no side effects in mount. Badge helper must return booleans for `:if`
(AGENTS.md §10).

## Safety review

- Sensitive records touched? yes — Manual body in admin forms (never rendered to viewer/operator-editable surfaces)
- AI output to end user possible? no new path
- Guardrails applied? admin-only routes + policy re-checks in actions
- Audit trail covered? writes go through 5.1 paper-trailed actions

## Out of scope (will NOT do in this story)

- Excerpt-text inspection UI (admins use `ai_prompt` provenance)
- Screenshot tooling (5.7 decides if needed)

## Verification

```bash
just verify
mix test test/ashy_walnut_desk_web/
```

## Notes during implementation

- Decisions made: archive/restore live inline on the index rows (no
  separate confirm step — both are reversible status flips); the badge
  helper treats a missing/blank mode as "none" so legacy drafts can
  never crash the panel.
- Spec drift noticed: none.
- Gotchas to add to AGENTS.md §10: none (gettext .pot produced via the
  ci.yml codegen job's gettext.extract step).
