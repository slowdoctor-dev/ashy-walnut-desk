# Story 5.1: Manual resource foundation (Knowledge axis)

**Phase**: 5
**Estimate**: 3h
**Depends on**: —
**Status**: done

---

## Goal

Ship the `Knowledge.Manual` Ash resource — authored operational
knowledge with revision counter, soft-delete, paper-trail, and
role-scoped policies — plus its migrations.

## Context

First story of Phase 5; everything else (chunks, embeddings,
retrieval) derives from Manual rows. Mirrors story 4.1 (Persona
foundation) in shape.

## Reference specs

- `/AGENTS.md` §6 code rules, §7 safety rules
- `/specs/phase-5/requirements.md` §2 (authoring AC), §3 scope
- `/specs/phase-5/architecture.md` §3.1, §10 migration plan
- `/specs/decisions/ADR-019-soft-delete-default.md`

## Acceptance criteria

- [x] AC1: `Knowledge.Manual` exists with attributes per architecture §3.1 (`title`, unique `slug`, sensitive `body` ≤ 64K, `revision` starting at 1, `status`, timestamps, `deleted_at`) and actions `:author`, `:revise` (bumps `revision`), `:archive`, `:restore`, `:soft_delete`, primary `read` filtering deleted rows. — Verify: `mix test test/ashy_walnut_desk/knowledge/manual_test.exs`
- [x] AC2: Policies enforce admin write / operator read / viewer nothing, across every action. — Verify: `mix test test/ashy_walnut_desk/knowledge/manual_policy_test.exs`
- [x] AC3: AshPaperTrail captures `:author`/`:revise`/`:archive` with sensitive redaction mode, and versions are admin-only. — Verify: `mix test test/ashy_walnut_desk/knowledge/manual_paper_trail_test.exs`
- [x] AC4: Generated migration applies cleanly and `mix ash_postgres.generate_migrations --check` stays green. — Verify: `mix ecto.migrate && mix ash_postgres.generate_migrations --check`

## Files to create

```
lib/ashy_walnut_desk/knowledge/manual.ex                     — Ash.Resource
priv/repo/migrations/<ts>_add_manuals.exs                    — generated
test/ashy_walnut_desk/knowledge/manual_test.exs              — actions/attrs
test/ashy_walnut_desk/knowledge/manual_policy_test.exs       — role matrix
test/ashy_walnut_desk/knowledge/manual_paper_trail_test.exs  — versioning
```

## Files to modify

```
lib/ashy_walnut_desk/knowledge/knowledge.ex   — register Manual
```

## Implementation notes

Clone the Persona resource's policy/paper-trail posture (story 4.1);
`revision` bump needs `require_atomic? false` (AGENTS.md §10 gotcha on
expr-policied updates). `:revise` accepts `[:title, :body]` only.
`EnqueueIndexing` is story 5.3 — do NOT wire job enqueue here.

## Safety review

- Sensitive records touched? yes — `body` is deployment knowledge (`sensitive? true`)
- AI output to end user possible? no (authoring only)
- Guardrails applied? policies + paper-trail redaction
- Audit trail covered? AshPaperTrail on all writes

## Out of scope (will NOT do in this story)

- Chunking/embedding (5.2–5.3), retrieval (5.4), LiveView (5.6)

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/knowledge/
```

## Notes during implementation

- Decisions made: archive is a status flip only (retrieval
  visibility), distinct from :soft_delete — unlike Persona where
  archive conflates both; Manual body is deliberately operator-readable
  (reference material), documented in the field policy.
- Spec drift noticed: none.
- Gotchas to add to AGENTS.md §10: none (migration produced via the
  ci.yml dispatch-only codegen job — see the [chore] commit).
