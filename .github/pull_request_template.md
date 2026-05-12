## Story

`[<N.M>]` <one-line summary>

Linked story: `specs/phase-<N>/stories/story-<N.M>.md`

Spec-only or meta PR? Drop the `[N.M]` prefix and link the affected spec/file instead.

## Summary

<2–3 bullets: what changed and why. Reference the spec rather than restating it.>

## Acceptance criteria

Copied from the story. Check off only after verifying.

- [ ] AC1: <criterion> — Verified by: `<command or test>`
- [ ] AC2: <criterion> — Verified by: `<command or test>`
- [ ] AC3: <criterion> — Verified by: `<command or test>`

## Verification

- [ ] `just verify` passes locally (format + credo --strict + test + spec-check)
- [ ] No new compiler warnings
- [ ] CI green

## Safety review

Required if the change touches sensitive records, AI output, or send paths.
Otherwise write `N/A`.

- Sensitive records touched? <yes/no — which>
- AI output reaches end user? <yes/no — how guarded>
- Guardrails applied? <Safety.Validator rules / Persona / Manual>
- Audit trail covered? <AshPaperTrail config / Oban worker logs>
- 5-second countdown still enforced on any send path? <yes/no/N-A>

## Spec drift

- [ ] No drift, OR
- [ ] Spec updated in this PR — link section
- [ ] New gotcha appended to AGENTS.md §10 (if discovered)

## Tool attribution

Implemented by: `claude` | `codex` | `human` (per `docs/using-claude-and-codex.md`)
