# Story 0.11: Phase 0 E2E magic-link integration test

**Phase**: 0
**Estimate**: 2h
**Depends on**: 0.6, 0.8
**Status**: ready

---

## Goal

One integration test that exercises the full Phase 0 magic-link flow end-to-end (request → email → confirm → authenticated session → WelcomeLive shows the user) and an explicit pass-through of the Phase 0 acceptance checklist in `requirements.md §2`.

## Context

Per `prompts/bmad-pm.md`, the last story of each phase is an integration test that verifies the phase's acceptance criteria compose into a working system. This story is the holistic gate — every preceding story's unit test catches its own scope; this story catches integration regressions across resource, action, policy, route, view, and email transport.

## Reference specs

- `/specs/phase-0/requirements.md` §2 (all phase-level ACs)
- `/specs/phase-0/architecture.md` §6.1 (magic-link sequence diagram)
- `/specs/phase-0/architecture.md` §11 (testing strategy — Integration row)

## Acceptance criteria

- [ ] AC1: A single Phoenix.LiveViewTest scenario in `test/integration/magic_link_e2e_test.exs` walks: visit `/sign-in` → submit a fresh email → Swoosh captures one email → extract token URL → visit the token URL → session is established → redirect lands on `/` → WelcomeLive renders the authenticated UI containing the user's email. Verify: `mix test test/integration/magic_link_e2e_test.exs` passes.
- [ ] AC2: The same test asserts role assignment: first registered user has `role: :admin`, a second user registered immediately after gets `role: :operator`. Verify: same test file asserts both roles via `Accounts.read!` after each registration.
- [ ] AC3: `specs/phase-0/requirements.md §2` checklist is updated — every box flips from `[ ]` to `[x]` because each AC is now demonstrably satisfied by the codebase. Verify: `grep -c "^- \[x\]" specs/phase-0/requirements.md` equals 12 (the count of AC bullets in §2).

## Files to create

```
test/integration/magic_link_e2e_test.exs   — the E2E test
```

## Files to modify

```
specs/phase-0/requirements.md   — flip §2 checklist boxes to [x]
```

## Implementation notes

- Use `Swoosh.TestAssertions.assert_email_sent/1` to capture the magic-link email; parse the token URL out of the body.
- Token URL visit can use `Phoenix.ConnTest.get/2`; assert the response sets a session cookie and the redirect lands on `/`.
- The test runs inside the Ecto sandbox; the partial-unique admin index from Story 0.6 still applies inside the transaction.

## Safety review

- Sensitive records touched? **Yes** — `User` + `Token`. The test fixture emails are fakers; AGENTS.md §9 (no real customer data) holds by construction.
- AI output to end user possible? **No**.
- Guardrails applied? All policies from earlier stories.
- Audit trail covered? Per 0.5's AshPaperTrail-on-User decision.

## Out of scope

- Performance / load testing — Phase 5 meta-ops.
- Browser-driver tests (Wallaby, Hound) — LiveView's in-process test suffices for Phase 0.
- Multi-tenant or workspace scoping — post-Season-1.

## Verification

```bash
just verify
mix test test/integration/magic_link_e2e_test.exs
grep -c "^- \[x\]" specs/phase-0/requirements.md   # expect 12
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
