# Story 2.9: Reproducible UX screenshots + phase docs sync

**Phase**: 2
**Estimate**: 2h
**Depends on**: 2.7, 2.8
**Status**: ready

---

## Goal

Add reproducible visual evidence and docs updates for Phase 2 operator flow states.

## Reference specs

- `/specs/phase-2/requirements.md` §2 (Playwright screenshots)
- `/AGENTS.md` §12 (post-task verification discipline)

## Acceptance criteria

- [ ] AC1: Committed screenshots exist for open Inbox, drafting, countdown, and executed states under `docs/phase-2-screenshots/`. — Verify: `ls docs/phase-2-screenshots`
- [ ] AC2: A reproducible command path (via `just`) captures/re-captures Phase 2 screenshots. — Verify: `just phase2-screenshots`
- [ ] AC3: Phase 2 story/docs references are updated to reflect implemented paths and commands. — Verify: `rg -n "phase2-screenshots|phase2-screenshots|audit.verify" docs specs README.md`

## Files to create

```
docs/phase-2-screenshots/*.png
scripts/capture-phase2-screenshots.*
```

## Files to modify

```
justfile
README.md
specs/phase-2/requirements.md
```

## Verification

```bash
just verify
just phase2-screenshots
```
