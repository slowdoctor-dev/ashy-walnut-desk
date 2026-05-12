# GSD Story Execution Prompt

> Use for daily story implementation.
> Works with any AI coding agent (Claude Code, Codex CLI, Cursor, Cline, Aider).
> Start a fresh session and paste this prompt.

Follow the 4-phase GSD workflow: Discuss → Plan → Execute → Verify.

---

You are implementing **one story** for ashy-walnut-desk.

## Step 0: Load context (mandatory)

Read in order:
1. `/AGENTS.md` (source of truth)
2. `/specs/architecture.md`
3. The story file: `/specs/phase-N/stories/story-N.X.md`
4. Any spec sections the story references
5. Existing code in modules the story will modify

## Step 1: Discuss (5-10 min)

Before writing any code:
- Confirm you understand the story's goal and acceptance criteria
- Identify which files will be created/modified
- Flag any ambiguities in the spec
- Flag any deviations from the architecture
- Ask the human if anything is unclear

Output a short summary:
> "I'll implement story N.X by:
>   - Creating: <files>
>   - Modifying: <files>
>   - Approach: <one paragraph>
>   - Verification: <how I'll check it works>
> Proceed?"

**Wait for human approval before Step 2.**

## Step 2: Plan (5 min)

Detailed plan:
- Order of file changes
- New tests to write
- Migration commands to run
- Any new dependencies needed

If any uncertainty, ask **before** coding. Never guess safety logic
(sensitive records, AI output validation, send-path enforcement).

## Step 3: Execute

Implement in this order:
1. New Ash resources / changes (with attributes, relationships, actions, policies)
2. Migrations: `mix ash_postgres.generate_migrations --name <desc>` then `mix ecto.migrate`
3. New LiveView components
4. New tests (write tests for invariants, not just happy path)
5. Update affected specs if behavior diverges from design

**Atomic principle**: one logical change at a time. If you find yourself
making a parallel unrelated change, stop and create a new story.

## Step 4: Verify

Run `just verify`:
- `mix format --check`
- `mix credo --strict`
- `mix test`
- `./scripts/spec-check.sh`

All must pass. If any fail:
- Fix the cause, not the symptom
- If spec needs updating to match new reality, update spec in same commit
- Re-run until green

Then update story STATUS file:
- Mark each acceptance criterion as ☑
- Note any spec drift discovered
- Note any new gotchas (append to AGENTS.md §10 in same commit)

## Step 5: Commit

Single commit, atomic:
```
git add .
git commit -m "[N.X] <story title>

<body: what changed, why, any deviations from spec>"
```

## NEVER

- Skip Step 1 (Discuss). Vibe is the failure mode here.
- Skip `just verify`. Even for "trivial" changes.
- Make changes outside the story's scope. If you find a bug, file a new story.
- Continue if the model is confused. Stop, re-read spec, ask human.
- Carry context to next story. Close session after commit.

## When done

Say:
> "Story N.X complete. Verification green. Committed as <commit hash>.
> Next ready story: N.Y. Close this session and start fresh for the next one."

---

Begin: which story are you implementing? (e.g., "story 0.1")
