# Story 3.7: AuditLive.Chain Admin Viewer + Policy Gate

**Phase**: 3
**Estimate**: 3h
**Depends on**: 3.4, 3.5
**Status**: planned

---

## Goal

Deliver `AuditLive.Chain` as an admin-only operational viewer for chain-topic event inspection and hash-continuity visibility aligned with CLI verification semantics.

## Context

Audit-chain inspection was deferred in prior phases (TO-14). With real provider traffic in Phase 3, admins need first-class UI visibility into chain continuity and outcomes.

## Reference specs

- `/AGENTS.md` §7.3 Audit trail mandatory
- `/specs/architecture.md` §4 Overview layer, §11 Security posture
- `/specs/phase-3/architecture.md` §1 Overview, §4 LiveView components (`AuditLive.Chain`)
- `/specs/decisions/ADR-024-inbound-intake-policy.md` (operational visibility implications)

## Acceptance criteria

- [ ] AC1: `AuditLive.Chain` route exists and is admin-only; non-admin authenticated users are denied. — Verify: `mix test test/ashy_walnut_desk_web/live/audit_live/authorization_test.exs`
- [ ] AC2: Viewer supports chain-topic filtering and paginated event listing for audit events. — Verify: `mix test test/ashy_walnut_desk_web/live/audit_live/chain_filtering_test.exs`
- [ ] AC3: Viewer displays hash-continuity status per row consistent with `mix audit.verify` semantics. — Verify: `mix test test/ashy_walnut_desk_web/live/audit_live/hash_continuity_test.exs`
- [ ] AC4: Tampered-chain fixture scenario is visually distinguishable in viewer and aligns with CLI failure. — Verify: `mix test test/ashy_walnut_desk_web/live/audit_live/tamper_visibility_test.exs && mix audit.verify; echo $?`

## Files to create

```
lib/ashy_walnut_desk_web/live/audit_live/chain.ex                                      — admin audit chain viewer liveview

test/ashy_walnut_desk_web/live/audit_live/authorization_test.exs                       — admin-only route tests

test/ashy_walnut_desk_web/live/audit_live/chain_filtering_test.exs                     — topic filter + pagination tests

test/ashy_walnut_desk_web/live/audit_live/hash_continuity_test.exs                     — continuity indicator tests

test/ashy_walnut_desk_web/live/audit_live/tamper_visibility_test.exs                   — tampered-chain UI/CLI alignment tests
```

## Files to modify

```
lib/ashy_walnut_desk_web/router.ex                                                     — add audit live route + authorization mount
lib/ashy_walnut_desk/interaction/audit_chain.ex                                        — expose helper(s) needed by viewer consistency checks
specs/phase-3/architecture.md                                                          — align route and behavior details
```

## Implementation notes

This story is read-only operational tooling. Do not add mutation actions in this viewer.

## Safety review

- Sensitive records touched? yes — audit event payload visibility in admin surface
- AI output to end user possible? no
- Guardrails applied? admin-only policy gate
- Audit trail covered? yes — viewer is directly tied to audit-chain continuity semantics

## Out of scope (will NOT do in this story)

- Webhook endpoint throttling and preflight docs bundle: deferred to story 3.8
- Additional admin observability dashboards beyond chain viewer: deferred to later phase

## Verification

```bash
just verify
# Plus story-specific:
mix test test/ashy_walnut_desk_web/live/audit_live/authorization_test.exs
mix test test/ashy_walnut_desk_web/live/audit_live/chain_filtering_test.exs
mix test test/ashy_walnut_desk_web/live/audit_live/hash_continuity_test.exs
mix test test/ashy_walnut_desk_web/live/audit_live/tamper_visibility_test.exs
mix audit.verify
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
