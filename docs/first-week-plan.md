# First-Week Plan

> Action guide for the first 7 days of Phase 0.
>
> The single source of truth is [`BASELINE.md`](../BASELINE.md). This file
> covers **only week 1 actions**.

---

## Where you are

✅ Stack chosen (Elixir + Ash — see BASELINE §5)
✅ Three-axis architecture defined (see `specs/architecture.md`)
✅ Methodology chosen (SDD with BMAD + GSD)
✅ Repo scaffolded
✅ Phase 0 requirements drafted, Story 0.1 ready as exemplar

🔜 **Phase 0 starts now**: BMAD Architect → PM → implementation.

---

## Day 1 — Environment + GitHub (2 hours)

### Morning (1 hour)

```bash
# 1. Create GitHub repo (in browser)
#    slowdoctor-dev/ashy-walnut-desk
#    Public, MIT, do NOT auto-create README

# 2. Extract this scaffold
mkdir -p ~/projects && cd ~/projects
tar xzf ~/Downloads/ashy-walnut-desk-init.tar.gz
cd ashy-walnut-desk-init
mv ../ashy-walnut-desk-init ../ashy-walnut-desk
cd ../ashy-walnut-desk

# 3. Initial commit
git init -b main
git add .
git commit -m "Initial scaffold (Phase -1 → 0 transition)"

# 4. Push
git remote add origin git@github.com:slowdoctor-dev/ashy-walnut-desk.git
git push -u origin main
```

### Afternoon (1 hour)

```bash
# 5. Tooling check
which just || brew install just     # or apt install just
which asdf || curl ...              # asdf installer
asdf install                        # installs from .tool-versions

# 6. Environment file
cp .env.example .env
# Fill in at minimum:
#   ANTHROPIC_API_KEY
#   SECRET_KEY_BASE        (generate: mix phx.gen.secret)
#   IDENTIFIER_HASH_SALT   (random 32-byte hex: openssl rand -hex 32)

# 7. Verify scaffold
just status      # should show "Phase 0, 1 story ready"
just --list      # show all available commands
```

---

## Day 2 — Phase 0 Architecture (BMAD Architect, ~2 hours)

**Goal**: produce `specs/phase-0/architecture.md` that answers the open
questions listed in `specs/phase-0/requirements.md` §7.

```bash
# Fresh AI session (Claude Code OR Codex CLI)
just architect-prompt
```

Then say:

> Phase 0. Read the files in order, then propose architecture section by section.

The Architect will:
1. Read AGENTS.md, BASELINE.md, architecture.md, phase-0/requirements.md
2. Propose a section-by-section design
3. Get confirmation on each section
4. Save `specs/phase-0/architecture.md`

End of Day 2: commit `specs/phase-0/architecture.md`.

---

## Day 3 — Phase 0 Story Breakdown (BMAD PM, ~3 hours)

**Goal**: stories for Phase 0 generated, each 1-3 hours, AC-tested.

```bash
# Fresh AI session
just pm-prompt
```

Then say:

> Phase 0. Story 0.1 is already drafted as exemplar. Read all reference
> files, then propose the list of remaining stories 0.2 through 0.M.
> Confirm the list before writing files.

The PM will:
1. Read the reference files (AGENTS.md, BASELINE.md, architecture, phase-0)
2. Propose a story list (titles + estimates + dependencies)
3. Get confirmation on the list
4. Write each story file using `_template.md`
5. Update `requirements.md §4` with the breakdown table

**Heuristics the PM enforces**:
- Each story 1-3h
- ≤ 5 ACs per story (else split)
- ≤ 5 files modified (else split)
- No frontend + backend in one story (split)
- Last story = integration test

End of Day 3: commit all `specs/phase-0/stories/story-0.*.md`.

---

## Day 4 — First Implementation (GSD, ~2 hours)

**Goal**: Story 0.1 complete and merged.

```bash
# Fresh AI session
just story-prompt
```

Then say:

> Implement story 0.1.

The agent will:
1. **Discuss** (5-10 min): summarize approach, wait for approval
2. **Plan** (5 min): list file changes
3. **Execute**: create files in the order listed in the story
4. **Verify**: run `just verify`
5. **Commit**: atomic, format `[0.1] description`

**At each Discuss step, you decide**: proceed, or push back?

End of Day 4: `git log` shows the first `[0.1]` commit, CI green.

---

## Day 5 — Continue Stories (~4 hours)

Same pattern as Day 4. Two stories = two fresh sessions = two commits.

If you finish early, try parallel work with both Claude Code and Codex
in separate git worktrees:

```bash
git worktree add ../awd-claude feature/story-0.4
git worktree add ../awd-codex feature/story-0.5
# Run Claude in one terminal, Codex in another
```

---

## Day 6 — Continue + Mid-Phase Check (~4 hours)

Continue implementation. If anything is going wrong:

- **Spec wrong?** → stop, run Architect persona again, update spec
- **Story too big?** → stop, run PM persona to split
- **AI confused?** → close session, reread spec, fresh session

---

## Day 7 — Catch-up + Phase 1 Prep (~3 hours)

- Finish any Phase 0 stories you wanted done in week 1
- Run BMAD Analyst persona to start drafting `specs/phase-1/requirements.md`
- Update CHANGELOG.md
- Push, verify CI green
- Self-retrospective:
  - What slowed you down?
  - What surprised you?
  - What gotchas should go in AGENTS.md §10?

---

## What to AVOID this week

1. **Multi-story session** — close the session after each story commit
2. **Skipping Discuss** — always summarize before coding
3. **Spec deferral** — if spec is wrong, fix it in the same commit
4. **Tool lock-in** — if you wrote Claude-only code, refactor
5. **"Just a quick fix"** — file a new story for any bug you find
6. **Verify bypass** — `just verify` always

## Daily checklist

```
Morning:
[ ] just status — what's done, what's next
[ ] Open fresh AI session for the first story of the day
[ ] Verify .env still has working API keys

End of day:
[ ] just status — what got done
[ ] git push — CI must be green
[ ] Close all AI sessions (no leftover context)
[ ] (Optional) brief note in scratch: what surprised me today
```

## End-of-week checklist

- [ ] Multiple stories merged to main
- [ ] All commits in `[N.M]` format
- [ ] CI green
- [ ] No spec-drift warnings (`just spec-check`)
- [ ] Phase 1 Analyst session started (Day 7)
- [ ] AGENTS.md §10 has new gotchas if discovered
- [ ] Confidence: "I can do this for several more months"

If end-of-week check fails on the last item: stop, reassess.
This is a marathon. Don't burn out in week 1.
