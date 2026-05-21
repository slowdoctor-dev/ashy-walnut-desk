# Story 4.5: Draft Generation State Machine + Worker-Gated Actions + Audit Events

**Phase**: 4
**Estimate**: 3h
**Depends on**: 4.1, 4.4
**Status**: done

---

## Goal

Implement Draft-level generation actions/status transitions and audit-event extensions so AI generation is fully represented in the chain before worker orchestration.

## Context

This story defines the authoritative state machine (`:generating` path) and policy gates that prevent operator-forged completion/failure transitions.

## Reference specs

- `/AGENTS.md` §7.2 human-in-the-loop, §7.3 audit trail mandatory
- `/specs/architecture.md` §8 data invariants
- `/specs/phase-4/architecture.md` §2 modified modules, §3.2 `Interaction.Draft`, §7 audit event extensions

## Acceptance criteria

- [x] AC1: `Draft` status enum and actions include `:generate`, `:complete_generation`, `:fail_generation` with valid transitions and policy gates. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_generation_actions_test.exs`
- [x] AC2: Worker-only completion/failure actions are blocked for regular actors and allowed only with generation-worker context check. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_generation_policy_test.exs`
- [x] AC3: `Draft.:approve` enforces validator-pass precondition and preserves existing countdown/send chain contract. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_approval_validation_gate_test.exs`
- [x] AC4: Generation lifecycle emits chain events (`requested/completed/failed`) with expected payload shapes. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_generation_audit_chain_test.exs`
- [x] AC5: `Draft.:approve` atomically supersedes every other `:drafting` candidate on the same Inbox in a single transaction; each supersession stamps its own `ChainLink :draft_superseded` event, and the approved draft's `:draft_approved` payload includes `superseded_sibling_draft_ids`. — Verify: `mix test test/ashy_walnut_desk/interaction/draft_approval_supersede_siblings_test.exs`

## Files to create

```
lib/ashy_walnut_desk/interaction/checks/from_generation_worker.ex             — worker-only action check
lib/ashy_walnut_desk/interaction/changes/supersede_sibling_draft_candidates.ex — atomic sibling-supersede on approve

test/ashy_walnut_desk/interaction/draft_generation_actions_test.exs            — status/action transitions
test/ashy_walnut_desk/interaction/draft_generation_policy_test.exs             — context gate tests
test/ashy_walnut_desk/interaction/draft_approval_validation_gate_test.exs      — validator gate on approve
test/ashy_walnut_desk/interaction/draft_approval_supersede_siblings_test.exs   — sibling-supersede atomicity
test/ashy_walnut_desk/interaction/draft_generation_audit_chain_test.exs        — event payload tests
```

## Files to modify

```
lib/ashy_walnut_desk/interaction/draft.ex                                   — statuses + generation actions + approve precondition
lib/ashy_walnut_desk/interaction/changes/chain_link.ex                      — new event types/payload fields
```

## Implementation notes

Keep orchestration out of this story: enqueueing/worker execution wiring is story 4.6.

## Safety review

- Sensitive records touched? yes — AI provenance fields and draft bodies
- AI output to end user possible? yes (draft review surface)
- Guardrails applied? validator-pass precondition + worker-only completion paths
- Audit trail covered? yes — chain event extensions

## Out of scope (will NOT do in this story)

- Oban worker implementation: deferred to story 4.6
- LiveView generation UX: deferred to story 4.7

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk/interaction/draft_generation_actions_test.exs
mix test test/ashy_walnut_desk/interaction/draft_generation_policy_test.exs
mix test test/ashy_walnut_desk/interaction/draft_approval_validation_gate_test.exs
mix test test/ashy_walnut_desk/interaction/draft_approval_supersede_siblings_test.exs
mix test test/ashy_walnut_desk/interaction/draft_generation_audit_chain_test.exs
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Mirrored existing worker gate mechanism with action context flag (`context.from_generation_worker == true`) to match `FromActionWorker` behavior.
- Spec drift noticed:
- `specs/phase-4/architecture.md §3.2` references a process-dictionary worker marker; implementation and test suite use context-flag worker checks. No code deviation needed; wording should be corrected in spec docs.
- Gotchas to add to AGENTS.md §10:
