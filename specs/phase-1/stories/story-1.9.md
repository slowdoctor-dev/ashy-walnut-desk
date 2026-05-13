# Story 1.9: Playwright screenshot evidence for Identity timeline UX

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.6
**Status**: ready

---

## Goal

Add reproducible Playwright screenshot capture for key Identity timeline UI states and commit evidence under `docs/phase-1-screenshots/`.

## Context

Phase 1 AC13 requires both automated LiveView integration tests and reproducible visual evidence generated via `just` workflow.

## Reference specs

- `/AGENTS.md` §5 (commands/workflow discipline)
- `/specs/phase-1/requirements.md` §2 (AC13)
- `/specs/phase-1/architecture.md` §2 (Tooling) and §11 (Manual/Playwright)

## Acceptance criteria

- [ ] AC1: `just screenshots` recipe exists and generates deterministic timeline-state screenshots against a running dev server. — Verify: `just screenshots`
- [ ] AC2: `docs/phase-1-screenshots/` contains committed screenshots covering create state and linked-record timeline state. — Verify: `ls -1 docs/phase-1-screenshots`
- [ ] AC3: A short doc note describes how to regenerate screenshots locally. — Verify: `grep -q "just screenshots" README.md`

## Files to create

```
docs/phase-1-screenshots/*   — committed screenshot evidence
scripts/screenshots-phase1.sh   — reproducible capture script (or equivalent)
```

## Files to modify

```
justfile   — add screenshots recipe
README.md   — add screenshot regeneration instructions
```

## Implementation notes

Keep screenshot generation deterministic and scriptable; avoid manual-only ad-hoc capture steps.

## Safety review

- Sensitive records touched? Uses fake fixture data only.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? N/A.

## Out of scope (will NOT do in this story)

- Functional integration assertions: deferred to 1.10
- CI visual diff gate: deferred to future hardening story

## Verification

```bash
just verify
just screenshots
ls -1 docs/phase-1-screenshots
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
