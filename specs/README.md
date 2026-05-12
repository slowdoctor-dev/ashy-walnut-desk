# Specifications

> Source of truth for what awd is and how it works.
> Code is derived from specs, not the other way around.

---

## Top-level files

- `architecture.md` — project-level architecture (immutable for v1)

## Subdirectories

```
specs/
├── architecture.md       — project-level architecture
├── 02-domain/            — resource specs (filled per phase)
├── phase-0/              — Foundation: requirements + Story 0.1
├── decisions/            — 17 ADRs (architectural decisions)
└── compliance/           — deployment-specific compliance (deployer fills)
```

Future phase directories (`phase-1/`, `phase-2/`, etc.) do not exist yet.
They are created when each phase starts. Their `requirements.md` is
written by the BMAD Analyst persona at that time, reflecting the actual
state of the project, learnings from prior phases, and the current
environment. See `docs/methodology.md`.

This is **just-in-time spec**, not pre-baking. Pre-baking a later phase
in month 1 freezes later-month decisions into month-1 thinking, which is
the opposite of what SDD wants.

## How to read

### As a new contributor (~20 min)

1. `BASELINE.md` (repo root) — what awd is, all decisions
2. `architecture.md` — three-axis structure
3. `decisions/README.md` — the 17 ADRs index
4. `phase-0/requirements.md` — current phase scope
5. `phase-0/stories/story-0.1.md` — exemplar story

### Before starting a new phase

1. Previous phase retrospective (if exists)
2. `BASELINE.md` (any updates)
3. Run BMAD Analyst persona — see `prompts/bmad-analyst.md`
4. Output goes to `specs/phase-N/requirements.md` (created at this point)

### Before implementing a story

1. The story file in `phase-N/stories/`
2. Architecture sections referenced from the story
3. Domain specs the story modifies
4. AGENTS.md (repo root)

## Spec status legend

- **Drafted**: contents present, ready for use
- **Skeleton**: scaffolded for filling at the appropriate time
- **Placeholder**: empty by design (filled by persona at phase start)

| Path | Status |
|---|---|
| `architecture.md` | Drafted |
| `phase-0/requirements.md` | Drafted |
| `phase-0/stories/_template.md` | Drafted |
| `phase-0/stories/story-0.1.md` | Drafted (exemplar) |
| `02-domain/README.md` | Drafted (index) |
| `compliance/README.md` | Drafted (index; deployer fills content) |
| `decisions/ADR-001.md` | Drafted (exemplar) |
| `decisions/ADR-002 .. ADR-015.md` | Skeleton (fill body before referencing) |
| `decisions/ADR-016 .. ADR-018.md` | Drafted |

## How specs evolve

```
At project start (now):
  AGENTS.md + BASELINE.md + architecture.md + Phase 0 are drafted.
  17 ADRs are in `decisions/` (some skeleton).

At each phase start:
  Run BMAD Analyst → write specs/phase-N/requirements.md
  Run BMAD Architect → write specs/phase-N/architecture.md
  Run BMAD PM → generate specs/phase-N/stories/story-N.M.md files

During each story:
  GSD execute updates story STATUS, modifies referenced specs if drift found.

At each phase end:
  Retrospective written: specs/phase-N/retrospective.md.
  Domain specs (02-domain/) updated with new resources from the phase.
  ADRs added if new decisions were made during the phase.
```

## When in doubt

If a spec is missing, write it before coding (or ask).
If a spec is contradictory, fix it before coding (or ask).
If a spec is outdated, fix it in the same commit as the code that diverged.

Specs are not optional documentation. They are the project itself.
