# Story 1.8: TO-3 token expunge schedule via AshOban

**Phase**: 1
**Estimate**: 1h
**Depends on**: 1.1
**Status**: ready

---

## Goal

Resolve TO-3 by scheduling recurring expired-token expunge and validating expired rows are removed while valid rows remain.

## Context

TO-3 was explicitly deferred from Phase 0 and is in-scope for Phase 1 but largely independent of Identity-resource implementation.

## Reference specs

- `/AGENTS.md` §10 gotchas (TO-3 context)
- `/specs/phase-1/requirements.md` §2 (AC14)
- `/specs/phase-1/architecture.md` §6.3 and §11 (Background/AshOban testing)
- `/specs/security/known-trade-offs.md` (TO-3)

## Acceptance criteria

- [ ] AC1: `Accounts.Token` has recurring expunge trigger configuration that calls `:expunge_expired`. — Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs`
- [ ] AC2: Regression test asserts expired token rows are deleted and unexpired rows are retained after trigger/action run. — Verify: `mix test test/ashy_walnut_desk/accounts/token_test.exs`
- [ ] AC3: No regressions in authentication token behavior under existing auth tests. — Verify: `mix test test/ashy_walnut_desk/accounts`

## Files to create

```
(none expected)
```

## Files to modify

```
lib/ashy_walnut_desk/accounts/token.ex   — add AshOban trigger config
test/ashy_walnut_desk/accounts/token_test.exs   — expunge schedule regression tests
config/runtime.exs   — only if scheduler config required by chosen trigger pattern
```

## Implementation notes

Prefer resource-local trigger configuration per architecture recommendation.

## Safety review

- Sensitive records touched? Yes — authentication token lifecycle records.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? Token hygiene story; audit not primary path.

## Out of scope (will NOT do in this story)

- Identity-axis resource behavior: covered in 1.2–1.7
- Deployment-specific retention policy windows: deferred to deployer repo

## Verification

```bash
just verify
mix test test/ashy_walnut_desk/accounts/token_test.exs
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
