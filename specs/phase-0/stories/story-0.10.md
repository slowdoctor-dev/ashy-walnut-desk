# Story 0.10: README quick-start verification + CHANGELOG Phase 0 update

**Phase**: 0
**Estimate**: 1h
**Depends on**: 0.8, 0.9
**Status**: ready

---

## Goal

Run the README quick-start end-to-end against a fresh clone, fix any drift discovered, and update `CHANGELOG.md`'s `[Unreleased]` section with the Phase 0 deliverables.

## Context

Requirements §2 require a working README quick-start. By this story all functional Phase 0 deliverables (extensions, Oban, AshPaperTrail config, auth, WelcomeLive, CI) have landed. The quick-start documented in `README.md` was authored ahead of implementation in Story 0.1 — this story is where it gets verified end-to-end against the actual code.

## Reference specs

- `/specs/phase-0/requirements.md` §2 (acceptance criteria — README quick-start)
- `/AGENTS.md` §5 (commands referenced by the quick-start)

## Acceptance criteria

- [ ] AC1: A fresh clone of the repo into a clean directory completes the README quick-start (`just setup`, `docker compose up -d`, `mix ecto.setup`, `just dev`, sign up via `/sign-in`, see WelcomeLive). Verify: `git clone . /tmp/awd-clone && cd /tmp/awd-clone && just setup && just verify` exits 0; manual: `just dev` and the sign-up loop completes.
- [ ] AC2: `CHANGELOG.md` `[Unreleased]` section lists, under "Phase 0 — Foundation", the deliverables: pgvector + pg_trgm extensions, Oban with four queues, AshPaperTrail at app level, AshAuthentication magic-link, first-user-admin, WelcomeLive, gettext baseline, GitHub Actions CI. Verify: `grep -A20 'Unreleased' CHANGELOG.md` contains each topic.
- [ ] AC3: `just verify` passes. Verify: `just verify` exits 0.

## Files to create

— (none)

## Files to modify

```
README.md       — refine quick-start if dry-run reveals gaps
CHANGELOG.md    — Phase 0 entries under [Unreleased]
```

## Implementation notes

- Treat this as a verification + documentation pass, not a feature-add. If the quick-start dry-run reveals a real bug, file a follow-up story rather than expanding this one.
- The CHANGELOG entries describe completed deliverables, not future work; phrase them in the past tense aligned with Keep a Changelog conventions.

## Safety review

N/A — documentation only; no resource or sensitive-data changes.

## Out of scope

- New features — any gap found becomes a follow-up story.
- Releasing a version tag — Phase 0 produces no released tag (`[0.0.0]` already documents the scaffold; the post-Phase-0 release is a Phase 5 concern).

## Verification

```bash
just verify
# Fresh-clone dry-run:
git clone . /tmp/awd-clone-$(date +%s)
cd /tmp/awd-clone-*
just setup
docker compose up -d
mix ecto.setup
just verify
```

## Notes during implementation

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
