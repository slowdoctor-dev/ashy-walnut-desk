# Methodology

## Why SDD

> "Vibe coding doesn't scale to 5-month projects."

This project will take ~5 months. Vibe coding (chatting with an AI,
accepting whatever it writes) breaks down past ~2 weeks because:

1. **Context rot** — AI sessions can't remember 200KB of context cleanly
2. **Spec drift** — code and intent diverge silently
3. **No paper trail** — decisions live in chat history, not in repo
4. **Single-agent dependency** — switching tools means re-explaining everything

**METR 2025 RCT**: experienced developers using AI tools predicted 24%
speedup, measured **19% slowdown** on multi-week projects. The longer
the project, the worse vibe coding gets.

**Decision**: adopt **Spec-Driven Development (SDD)**.
Specs are first-class, code is derived. AI sessions are ephemeral; specs
are durable. Any AI agent can pick up any spec and produce equivalent code.

## Two methodologies, complementary

### BMAD (per phase, ~half day)

BMAD-METHOD (https://github.com/bmadcode/BMAD-METHOD) — 12+ AI personas,
MIT-licensed, popular for waterfall-style phase planning.

We use **3 personas** at the start of each phase:

| Persona | Role | Output |
|---|---|---|
| **Analyst** | Clarify requirements | `specs/phase-N/requirements.md` |
| **Architect** | Technical design | `specs/phase-N/architecture.md` |
| **PM** | Story breakdown | `specs/phase-N/stories/story-N.M.md` |

These are role-playing prompts in `prompts/bmad-*.md`. You activate one
by starting a fresh AI session and pasting the prompt.

### GSD (per story, 1-3 hours)

Get Shit Done (https://gsdcoding.com) — 4-phase workflow for daily
implementation. Lightweight, fits Claude Code/Codex native usage.

| Phase | Action |
|---|---|
| **Discuss** | Load story + read specs + propose approach |
| **Plan** | Detailed file changes BEFORE coding |
| **Execute** | Implement; one story = one PR |
| **Verify** | `just verify` passes; update STATUS |

Daily story execution uses `prompts/gsd-execute-story.md`.

## Four core principles for large AI projects

1. **External state must live in files & git, not LLM context.**
   - Specs in `/specs/` (versioned)
   - Decisions in `/specs/decisions/` (ADRs)
   - Story progress in story `STATUS` sections
   - Chat history is **disposable**

2. **Context rotation.**
   - After each story: close session, start fresh
   - Spec is the bridge between sessions
   - Never "continue from yesterday's chat"

3. **Living specs.**
   - When code diverges from spec: update spec **in same commit**
   - Spec drift detected by `scripts/spec-check.sh`
   - Outdated spec is worse than no spec

4. **Automatic gates.**
   - `just verify` runs format + credo + test + spec-check
   - AI self-checks before declaring done
   - CI re-verifies on push

## Story discipline

A **story** = atomic unit of work.

Rules:
- **Size**: 1-3 hours of focused work
- **Independence**: one PR, one commit (squash-merge to main)
- **Acceptance criteria**: testable, runnable verification commands
- **Dependencies**: depend only on prior stories, no circular deps
- **AI-executable**: any agent should produce equivalent code from the spec

If a story is too big: split it. Heuristics in `prompts/bmad-pm.md`.

If a story is unclear: stop, go back to Architect persona to clarify.

## Phase discipline

A **phase** = a working system increment.

Phase 0 doesn't try to do everything. It produces a foundation
(skeleton + auth + CI). Phase 1 builds on it (Identity-axis resources). Etc.

Each phase ends with:
- **Integration story** (last story): verify all phase ACs end-to-end
- **Retrospective**: `specs/phase-N/retrospective.md` — what worked, what didn't
- **Next-phase prep**: Analyst persona for phase N+1

## The recursive insight

> "The methodology mirrors the product."

ashy-walnut-desk is a digital front desk that **learns from operation**
(Manuals, Personas, Guardrails evolve through use).

The way we **build** it works the same way:
- Specs evolve through phases (like manuals)
- Personas (Analyst/Architect/PM) replace ad-hoc prompting
- Guardrails (verification gates) catch drift

The build process is the product. If SDD works for building it, the
product is more likely to work for regulated-service organizations that
need to **operate** with the same discipline.

## When NOT to use SDD

This methodology is overhead. Don't apply it to:
- Throwaway scripts (single-use)
- Exploratory prototypes (< 1 week)
- One-file fixes

SDD pays off when:
- Project lifespan > 1 month
- Multiple AI tools / agents involved
- Multiple humans involved (now or future)
- Compliance or safety stakes (this one)

For this project: SDD is mandatory.

## How vibe creeps back in

Even with SDD, vibe coding tries to sneak back. Common failure modes:

1. **"Quick fix"** — bypassing spec to fix a bug. *No: file a new story.*
2. **Multi-story session** — implementing two stories in one chat. *No: fresh session each.*
3. **Skipping Discuss** — jumping to code. *No: always Discuss first.*
4. **Skipping verify** — "it's obviously fine". *No: gates exist for a reason.*
5. **Spec deferral** — "I'll update the spec later". *No: same commit.*
6. **Tool-specific code** — using a Claude-only feature. *No: must work cross-tool.*

If you catch yourself doing any of these: stop, restart the session,
re-read the spec.

## References

- BMAD-METHOD: https://github.com/bmadcode/BMAD-METHOD
- GSD: https://gsdcoding.com
- METR 2025 RCT: https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/
- Spec-Driven Development overview: https://github.com/agentic-spec/spec-driven-development
- AGENTS.md standard: https://agents.md
