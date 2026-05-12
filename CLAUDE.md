# Claude Code Instructions

See @AGENTS.md for project context, architecture, methodology, and conventions.
For session startup: read @BASELINE.md first (single entry point).

---

## Claude Code-specific notes

The above import (`@AGENTS.md`) is the source of truth. Everything in
AGENTS.md applies. Read it first.

This file adds only Claude Code-specific tips. Do NOT duplicate AGENTS.md.

### Suggested division with Codex

Both Claude Code and Codex CLI are equally welcome. Suggested split based
on each tool's typical strengths:

| Task type | Suggested tool |
|---|---|
| Long-context refactors, multi-file orchestration | Claude Code |
| Architecture/ADR drafting, deep research | Claude Code |
| Spec writing (BMAD phases) | Claude Code |
| Well-scoped story implementation | Either |
| Test generation, boilerplate | Either (try Codex first for speed) |
| Quick single-file edits | Codex |

Use git worktrees if running both in parallel:
```bash
git worktree add ../awd-claude feature/story-N.M
git worktree add ../awd-codex feature/story-N.K
```

### Slash command equivalents

Claude Code slash commands map to files in `prompts/`. From any agent:

```bash
just analyst-prompt   # → prompts/bmad-analyst.md
just architect-prompt # → prompts/bmad-architect.md
just pm-prompt        # → prompts/bmad-pm.md
just story-prompt     # → prompts/gsd-execute-story.md
```

### Don't depend on Claude-only features

Per AGENTS.md §9: production code must work across all AI tools. If you
use a Claude-specific feature (e.g., subagents, MCP tools), it should
stay in dev workflow only, never in shipped code.
