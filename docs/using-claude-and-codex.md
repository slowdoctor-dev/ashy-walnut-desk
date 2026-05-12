# Using Claude Code and Codex CLI Together

> This project is LLM-agnostic. Both tools (and Cursor, Cline, Aider, etc.)
> read the same `AGENTS.md` and produce equivalent results.
>
> This guide is for users running **both** Claude Code and Codex CLI.

## Why use both

- **Rate limit distribution** — alternating saves API quota
- **Strengths exploitation** — different models excel at different tasks
- **Resilience** — if one tool's API is down, switch

## Round-robin delegation

The pattern: one human, two AI agents, alternating per story.

```
Story 0.1  → Claude Code     (session 1, fresh context)
Story 0.2  → Codex CLI       (session 2, fresh context)
Story 0.3  → Claude Code     (session 3, fresh context)
...
```

Why this works:
- Each story is independent (SDD discipline)
- Each session is fresh (no carryover)
- Both tools read the same `AGENTS.md` → equivalent context
- Spec, not chat, is the bridge between sessions

## Parallel work via git worktrees

When you want both agents working simultaneously:

```bash
# In main worktree (Claude Code)
cd ~/projects/ashy-walnut-desk
git worktree add ../awd-claude feature/story-0.4

# In second worktree (Codex CLI)
git worktree add ../awd-codex feature/story-0.5

# Now run:
# Terminal 1: cd ../awd-claude && claude
# Terminal 2: cd ../awd-codex && codex

# Both can work simultaneously without file conflicts
```

After merge:
```bash
git worktree remove ../awd-claude
git worktree remove ../awd-codex
```

## Suggested division of labor

Based on each tool's typical strengths (not absolutes):

| Task type | Suggested tool | Why |
|---|---|---|
| Long-context refactors | Claude Code | Better at multi-file orchestration |
| Architecture/ADR drafting | Claude Code | Deeper reasoning on trade-offs |
| BMAD persona sessions (Analyst/Architect/PM) | Claude Code | Long-form structured output |
| Well-scoped story implementation | Either | Both excel here |
| Test generation, boilerplate | Codex (try first) | Faster, often cheaper |
| Single-file quick fixes | Codex | Lower latency |
| Code review (9-axis) | Claude Code | Subagent dispatch helpful |
| Migration generation | Either | Both handle Ash patterns |

**Important**: this is heuristic, not rule. If Codex feels right for a
refactor, use it. If Claude feels right for a quick fix, use it.

## One-agent-per-file rule

Never run both agents editing the same file at the same time. Conflicts
will happen. Git is the coordinator, but human discipline is required.

If you must work the same area:
1. Finish one story (commit) before starting the next
2. Or use git worktrees on different branches

## Cost monitoring

| Tool | Pricing model | Monitoring |
|---|---|---|
| Claude Code | Max 5x subscription ($100/mo flat) | No per-task cost |
| Codex CLI | OpenAI API per-token | Track via OpenAI dashboard |

If you find Codex API costs exceeding $50/mo:
- Reserve Codex for short tasks
- Use Claude Code for long-context work (already paid via subscription)

## What both tools share

Both read these files (you maintain once):

1. **AGENTS.md** — universal source of truth
2. **BASELINE.md** — all decisions
3. **specs/** — phase requirements, architecture, stories
4. **prompts/** — BMAD + GSD personas

Both produce these (interchangeable):

1. Story implementations (one PR per story)
2. Spec drafts (BMAD output)
3. Documentation updates
4. Tests

## What's tool-specific

**Claude Code only**:
- Subagents (parallel dispatch within one session)
- MCP tool integrations
- Skills (folder-based reusable prompts)

**Codex CLI only**:
- `--full-auto` mode (sandboxed execution)
- OpenAI-specific models (GPT-5, etc.)

These don't affect the repo. They affect how each tool operates internally.
Per AGENTS.md §9: production code must not depend on tool-specific features.

## Common pitfalls

### "Claude wrote this differently than Codex would"

Both tools produce code that satisfies the spec. Code style differences
are normal. Format normalizer (`mix format`) and Credo strict mode
flatten most differences.

If you notice systematic differences:
- Add to AGENTS.md §6 (Standards)
- Or to `.formatter.exs` / `.credo.exs`

### "I forgot which tool was working on what"

Use commit messages: `[0.4] description (claude)` or `[0.5] description (codex)`.
Not mandatory, but helpful for retrospectives.

### "One tool's output is much better"

Note it in the next phase retrospective. If a pattern emerges, update the
"suggested tool" table above.

### "The tools disagree on architecture"

Don't ask both. Ask one (Architect persona), commit the spec, then
implementation by either is equivalent.

## When to use only one

Both is overhead. Use only one tool if:
- You're new to the project (start with what you know)
- One tool has API issues (don't dual-debug)
- You're doing a critical session (safety review, etc.)
- You're learning (one tool's patterns at a time)

## Cross-tool review

For any safety-critical change (sensitive records, AI output, send paths),
consider:
1. Story implemented by Tool A
2. Code review by Tool B (run `just review-prompt`)

This catches tool-specific blindspots. Especially valuable for safety
guardrails.
