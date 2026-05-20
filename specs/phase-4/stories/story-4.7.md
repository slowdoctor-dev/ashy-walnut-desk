# Story 4.7: InboxLive Generation UX (Panel, Validator Badge, Candidate Flow, Gettext Errors)

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.5, 4.6
**Status**: planned

---

## Goal

Expose Phase 4 generation capabilities in `InboxLive.Show` with safe operator/admin UX: generate, observe validator outcomes, and manage candidate drafts without bypassing chain controls.

## Context

Backend generation is complete after story 4.6; this story adds operator-facing controls and status visibility while preserving existing approval/countdown behavior.

## Reference specs

- `/AGENTS.md` §6 gettext/user-facing strings, §7.2 human-in-the-loop
- `/specs/architecture.md` §1 overview, §12 testing strategy
- `/specs/phase-4/architecture.md` §2 web modules, §10 UI behavior

## Acceptance criteria

- [ ] AC1: `GenerationPanel` allows operator/admin to request generation and renders worker progress/state safely. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/generation_panel_test.exs`
- [ ] AC2: `ValidatorBadge` surfaces pass/fail + violation summary from persisted validator output without exposing restricted fields to viewers. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/validator_badge_test.exs`
- [ ] AC3: Candidate carousel renders one card per `:drafting` Draft on the Inbox; each card shows `ValidatorBadge` + body preview + per-card Approve/Reject/Regenerate actions; approve auto-supersedes sibling candidates (per story 4.5 AC5) and the carousel re-renders without leaving stale candidate cards visible. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/candidate_flow_test.exs`
- [ ] AC4: Operator-facing generation/validation error messages in this flow are gettext-backed. — Verify: `mix test test/ashy_walnut_desk_web/live/inbox_live/generation_i18n_test.exs`

## Files to create

```
lib/ashy_walnut_desk_web/live/inbox_live/components/generation_panel.ex      — generation controls/state
lib/ashy_walnut_desk_web/live/inbox_live/components/validator_badge.ex       — validator status component

test/ashy_walnut_desk_web/live/inbox_live/generation_panel_test.exs
test/ashy_walnut_desk_web/live/inbox_live/validator_badge_test.exs
test/ashy_walnut_desk_web/live/inbox_live/candidate_flow_test.exs
test/ashy_walnut_desk_web/live/inbox_live/generation_i18n_test.exs
```

## Files to modify

```
lib/ashy_walnut_desk_web/live/inbox_live/show.ex                              — integrate generation components/events
priv/gettext/default.pot                                                      — extracted keys
priv/gettext/*.po                                                             — localized strings
```

## Implementation notes

Preserve existing Phase 3 compensation/send UX and do not add any send bypass affordance.

## Safety review

- Sensitive records touched? yes — draft AI/provenance fields rendered
- AI output to end user possible? yes — operator review surface
- Guardrails applied? validator result gating + role-based field policies
- Audit trail covered? yes — transitions are backend actions only

## Out of scope (will NOT do in this story)

- Anthropic/provider changes: deferred to story 4.3
- Preflight/integration gate + deployer docs: deferred to story 4.8

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk_web/live/inbox_live/generation_panel_test.exs
mix test test/ashy_walnut_desk_web/live/inbox_live/validator_badge_test.exs
mix test test/ashy_walnut_desk_web/live/inbox_live/candidate_flow_test.exs
mix test test/ashy_walnut_desk_web/live/inbox_live/generation_i18n_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
