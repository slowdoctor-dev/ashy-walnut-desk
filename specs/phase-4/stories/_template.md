# Story <N.M>: <Short title>

**Phase**: <N>
**Estimate**: <1h | 2h | 3h>
**Depends on**: <previous story IDs, or — for first story>
**Status**: ready | in-progress | done | blocked

---

## Goal

One sentence: what this story delivers.

## Context

Why this story exists. What previous story enabled it. What it unblocks.

## Reference specs

- `/AGENTS.md` § <relevant section>
- `/specs/architecture.md` § <relevant section>
- `/specs/phase-N/architecture.md` § <relevant section>

## Acceptance criteria

Each criterion must be **testable** — write the verification command.

- [ ] AC1: <criterion> — Verify: `<command or test>`
- [ ] AC2: <criterion> — Verify: `<command or test>`
- [ ] AC3: <criterion> — Verify: `<command or test>`

(Aim for 3-5 ACs. If more than 5, split the story.)

## Files to create

```
path/to/new_file.ex   — purpose
```

## Files to modify

```
path/to/existing.ex   — what change
```

## Implementation notes

Brief notes on approach. Reference specs rather than duplicating them.
Flag any spec ambiguity.

## Safety review

(Required for any story touching sensitive records, AI output, or send paths. Skip with explicit "N/A" otherwise.)

- Sensitive records touched? <yes/no, what>
- AI output to end user possible? <yes/no, how>
- Guardrails applied? <which>
- Audit trail covered? <which AshPaperTrail config>

## Out of scope (will NOT do in this story)

- <thing>: deferred to story X.Y
- <thing>: deferred to phase N+1

## Verification

```bash
just verify   # all gates pass
# Plus story-specific:
# <commands>
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
