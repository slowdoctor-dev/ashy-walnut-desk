# Story 4.1: Persona Foundation (Knowledge Domain + Resource + Admin Surface Skeleton)

**Phase**: 4
**Estimate**: 2h
**Depends on**: —
**Status**: planned

---

## Goal

Establish the Phase 4 foundational Knowledge surface by shipping `Knowledge.Persona` with admin-governed lifecycle and operator-readable selection metadata.

## Context

Phase 4 generation depends on deployment-configured persona inputs (system prompt/disclosure/model override). This story creates the authoritative resource and minimal admin surface before AI pipeline stories.

## Reference specs

- `/AGENTS.md` §6 Code rules, §7 Safety Rules
- `/specs/architecture.md` §2 Three coequal axes, §11 Security posture
- `/specs/phase-4/architecture.md` §2 Affected modules, §3.1 `Knowledge.Persona`

## Acceptance criteria

- [ ] AC1: `Knowledge` domain and `Knowledge.Persona` resource exist with required fields and constraints (`slug` unique, `status`, `system_prompt`, `disclosure_text`, optional `model_override`). — Verify: `mix test test/ashy_walnut_desk/knowledge/persona_test.exs`
- [ ] AC2: Persona policies enforce admin mutate and admin/operator read semantics; sensitive internals stay field-policy gated per architecture. — Verify: `mix test test/ashy_walnut_desk/knowledge/persona_policy_test.exs`
- [ ] AC3: Persona supports soft-delete + paper-trail audit semantics (archive/recover and version rows). — Verify: `mix test test/ashy_walnut_desk/knowledge/persona_paper_trail_test.exs`
- [ ] AC4: Admin-only LiveView scaffold for Persona list/form exists and route is policy-gated. — Verify: `mix test test/ashy_walnut_desk_web/live/persona_live/access_test.exs`

## Files to create

```
lib/ashy_walnut_desk/knowledge/knowledge.ex                    — Ash.Domain for Knowledge axis
lib/ashy_walnut_desk/knowledge/persona.ex                      — Persona resource
lib/ashy_walnut_desk_web/live/persona_live/index.ex            — admin list surface
lib/ashy_walnut_desk_web/live/persona_live/form.ex             — admin form surface

 test/ashy_walnut_desk/knowledge/persona_test.exs              — schema/action tests
 test/ashy_walnut_desk/knowledge/persona_policy_test.exs       — policy/field policy tests
 test/ashy_walnut_desk/knowledge/persona_paper_trail_test.exs  — audit/version tests
 test/ashy_walnut_desk_web/live/persona_live/access_test.exs   — route/authz tests
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                             — add Persona admin routes
lib/ashy_walnut_desk_web/navigation.ex (or equivalent)         — admin nav link if present
```

## Implementation notes

Keep this story strictly foundational. Do not wire AI generation or worker logic yet. Ensure user-facing labels/errors in this surface are gettext-backed.

## Safety review

- Sensitive records touched? yes — persona prompt/disclosure/guardrail content
- AI output to end user possible? no
- Guardrails applied? field policies + admin-only mutation
- Audit trail covered? yes — paper trail on Persona

## Out of scope (will NOT do in this story)

- AI adapter/provider calls: deferred to story 4.2/4.3
- Safety validator runtime: deferred to story 4.4
- Draft generation actions/UI: deferred to stories 4.5-4.7

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/knowledge/persona_test.exs
mix test test/ashy_walnut_desk/knowledge/persona_policy_test.exs
mix test test/ashy_walnut_desk/knowledge/persona_paper_trail_test.exs
mix test test/ashy_walnut_desk_web/live/persona_live/access_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
