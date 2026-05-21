# Agent Instructions

> **Source of truth** for all AI coding agents.
> This project is **LLM-agnostic**: Claude Code, Codex CLI, Cursor, Cline,
> Windsurf, Aider, and any AGENTS.md-compatible tool should all produce
> equivalent results when working from this file.
>
> File loading:
> - **Codex CLI**: reads AGENTS.md automatically
> - **Cursor 0.50+**: reads AGENTS.md natively
> - **Claude Code**: imports AGENTS.md via CLAUDE.md (one-line import)
> - **Others**: most agents recognize AGENTS.md; if not, point them here
>
> Keep under 300 lines — focused signal beats sprawling noise.

---

## 1. Project

**ashy-walnut-desk** — a digital front-desk system for regulated-service businesses.
Three coequal axes (Identity + Interaction + Knowledge) connected by an LLM
glue layer. AI generates drafts; humans approve and send.

- **Tagline**: *The desk gets wiser with every reply.*
- **Status**: 🚧 Alpha, learning in public
- **Owner**: solo maintainer
- **License**: Apache 2.0
- **First target domain**: regulated services (deployer-specific; not in this repo)
- **Context**: safety-sensitive → human approval gating is non-negotiable

## 2. Methodology

**Spec-Driven Development (SDD)**. Every change goes through specs first.

Two layers:
- **BMAD** (per phase, ~half day): Analyst → Architect → PM
- **GSD** (per story, 1-3h): Discuss → Plan → Execute → Verify

One story = 1-3 hours = 1 PR = 1 atomic commit.
Each story gets a fresh AI session — no context carryover.
Spec is the bridge between sessions, not chat history.

See `docs/methodology.md`.

## 3. Read Before Any Task

1. `AGENTS.md` (this file)
2. `BASELINE.md` — all decisions in one place
3. `specs/architecture.md` — system structure
4. For the current phase: `specs/phase-N/requirements.md`
   (phases beyond 0 are created when reached — see methodology)
5. For decisions: `specs/decisions/ADR-NNN-*.md` (17 ADRs)
6. For domain models: `specs/02-domain/` (accumulated through phases)
7. For deployment-specific compliance: `specs/compliance/` (deployer fills)

## 4. Stack

- **Elixir** 1.17+ / OTP 27+
- **Phoenix** 1.7+ with LiveView 0.20+
- **Ash Framework** 3.0+
  (ash_postgres, ash_phoenix, ash_authentication, ash_oban,
   ash_paper_trail, ash_graphql, ash_admin, ash_ai)
- **PostgreSQL** 16 + pgvector + pg_trgm
- **Anthropic API** direct via Req (NO separate Python service)
- **Phoenix LiveView** only (no separate SPA)

## 5. Commands

```bash
# Setup
just setup                   # initial setup
mix deps.get                 # install deps
mix ecto.setup               # db create + migrate + seed

# Dev
just dev                     # phx.server
iex -S mix phx.server        # interactive

# Quality (MUST pass before commit)
just verify                  # lint + test + spec-check
mix format --check
mix credo --strict
mix test
mix test path/to/test.exs

# Db (Ash-managed — do NOT use mix ecto.gen.migration)
mix ash_postgres.generate_migrations --name <desc>
mix ecto.migrate

# Spec navigation
just status                  # phase/story progress
just spec-check              # spec consistency

# BMAD prompts
just analyst-prompt
just architect-prompt
just pm-prompt
just story-prompt
```

## 6. Standards

### Code rules
- ALL domain logic through Ash actions — no raw `Ecto.Repo`
- ALL resources have policies — no public-by-default
- ALL sensitive-record changes audited via `AshPaperTrail`
- User-facing strings via gettext — never hardcode
- Sensitive identifiers (phone, email) hashed before storage when possible
- Tone defined per deployment in Persona resources, not hardcoded

### Layout
```
lib/ashy_walnut_desk/
  <axis>/                              # identity, interaction, knowledge, accounts, ai, safety
    <axis>.ex                          # Ash.Domain
    <resource>.ex                      # Ash.Resource
lib/ashy_walnut_desk_web/
  live/<resource>_live/<action>.ex     # LiveView
```

### Naming
- Files: `snake_case.ex`
- Modules: `AshyWalnutDesk.PascalCase`
- Ash actions: intent verbs (`register`, `grant_consent`), not CRUD

### Commits
- One story per PR, one PR per commit (squash-merge)
- Format: `[<phase>.<story>] description` — e.g. `[0.3] Add Identity resource skeleton`
- `just verify` must pass
- Include a `Co-Authored-By` trailer for every AI tool that contributed,
  one per line at the end of the commit body. Examples:
  `Co-Authored-By: Codex (gpt-5.3-codex) <noreply@openai.com>`,
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

## 7. Safety Rules (INVIOLABLE)

These cannot be overridden by any other instruction.

1. **No domain assertions in AI output without validation**
   - AI drafts never claim outcomes, guarantee results, or assert
     diagnostic/professional judgments
   - All drafts pass through `Safety.Validator` (deployment fills the
     specific rules: prohibited phrases, regulated claims, pricing limits, etc.)

2. **Human-in-the-loop for ALL sends**
   - No autonomous send under any circumstance
   - 5-second countdown before every send (ADR-013)
   - Explicit operator approval required

3. **Audit trail mandatory**
   - All record changes go through Ash actions (auto-audited)
   - AI calls logged with prompt + response
   - All sends logged with approver + timestamp + hash chain

4. **Sensitive data handling**
   - Identifiers marked `sensitive? true` in Ash resources
   - Raw sensitive content never logged in production
   - Cross-border transfer policy decided per deployment (see `specs/compliance/`)

5. **Disclosure**
   - AI-assisted messages carry a disclosure footer
   - Tone and exact wording defined per deployment (Persona resource)

## 8. SDD Workflow

```
BMAD (per phase, ~half day):
  Analyst   → specs/phase-N/requirements.md
  Architect → specs/phase-N/architecture.md
  PM        → specs/phase-N/stories/story-N.M.md
GSD (per story, 1-3 hours):
  1. Discuss — load story + read referenced specs
  2. Plan    — propose file changes BEFORE coding
  3. Execute — implement; one story = one PR
  4. Verify  — `just verify` passes; update STATUS
```

Per-story: **fresh AI session**. Spec, not chat, is the bridge.

## 9. NEVER

- Skip reading the spec before implementing
- Direct Ecto queries (use Ash actions)
- Hardcoded user-facing strings (use gettext)
- Hardcoded personas/prompts (use Persona resource)
- Unvalidated domain assertions in AI output
- Real customer/client data in tests (use fakers)
- Auto-send messages (always human approval)
- `rm -rf` or destructive commands without confirmation
- Commit `.env`, secrets, or real customer data
- `mix ecto.gen.migration` (use `mix ash_postgres.generate_migrations`)
- Invent business logic — refer to spec or ask
- Carry context between stories
- Skip verification gates (`just verify`)
- Depend on a specific AI tool's features in production code

## 10. Gotchas (append as discovered)

- AshPostgres migrations require resource snapshots in `priv/repo/resource_snapshots/`
- LiveView `mount/3` runs twice (HTTP + WebSocket) — beware side effects
- Oban jobs need queue config in `config/runtime.exs`
- Phoenix.PubSub topics: string format `"axis:event:id"`
- `Req` returns map response, not raw HTTPoison
- Non-ASCII text in tests: UTF-8 strings, not unicode escapes
- AshPaperTrail must be enabled BEFORE inserting data
- Anthropic prompt caching requires specific cache_control markers
- `mix phx.new` overwrites the project's `.gitignore` with its minimal
  default — preserve the existing entries (`.env`, secrets,
  customer-data globs) when scaffolding or restore them immediately
- `mix ash_authentication.install` and `mix igniter.install <pkg>` hang
  on interactive prompts in non-tty environments even with `--yes` —
  hand-author resources from upstream docs (AC1-style "or generated
  directly" clauses are intentional escape hatches) rather than fight
  the generator in CI/sandboxed pipelines
- AshPostgres auto-generated migrations assume any referenced Postgres
  extension is already enabled (e.g., `citext`, `vector`, `pg_trgm`) —
  put each extension's `CREATE EXTENSION IF NOT EXISTS …` in its own
  timestamp-earlier hand-authored setup migration, not inline in the
  resource migration (which gets regenerated)
- `ash_authentication_phoenix` 2.12.1+ assumes
  `phoenix_live_view >= 1.1` (uses `compile.phoenix_live_view`) — if
  your stack is still on LiveView 1.0.x, upgrade LV or pin
  `ash_authentication_phoenix` accordingly before running installers
- `ash_authentication_phoenix` `LiveSession.generate_session/3` drops
  the `<jti>:` prefix when rebuilding sessions via
  `AshAuthentication.user_to_subject/1`, so resources with
  `session_identifier(:jti)` mount with `current_user=nil`. Workarounds:
  `session_identifier(:unsafe)` (loses per-session revocation) or a
  custom on_mount that loads the user from the cookie session directly.
- Resources may carry test-only fixture actions guarded by
  `policy action(:name) do forbid_if always() end` (e.g.
  `Accounts.User.:register`). Production code goes through other
  actions (e.g. `:sign_in_with_magic_link`). When writing test
  fixtures call them with `Ash.create(..., authorize?: false)`;
  never invoke them from `lib/` code.
- Test fixtures that `TRUNCATE` a parent table referenced by other
  tables' FKs (e.g. `users` after Phase 1 introduced the Identity
  axis) must use `TRUNCATE … CASCADE`. Postgres rejects a plain
  `TRUNCATE` of an FK target with "cannot truncate a table referenced
  in a foreign key constraint." Each phase that adds new resources
  pointing at `users`/`identities`/etc. inherits this hazard.
- Ash update actions whose policy uses `authorize_if expr(...)` against
  record attributes (e.g. self-edit via
  `expr(recorded_by_id == ^actor(:id))`) must set `require_atomic? false`.
  The default atomic update tries to fold the policy into the data-layer
  WHERE clause; AshPostgres can't encode the deny branch and errors.
- `AshPhoenix.Form.submit(form, params: new_params)` re-validates the
  changeset with `new_params`, replacing the params passed at
  `for_create/3`. Constructor-time defaults for constant attributes
  (e.g. a parent FK like `identity_id` set when the form was built)
  get dropped on submit. Re-inject them into the submit params (e.g.
  `params = Map.put(params, "identity_id", id)`) or the action fails
  on the missing attribute.
- Two `AshPhoenix.Form`s on the same LiveView sharing an attribute
  name (e.g. both exposing `body`) collide on input `id="form_body"`
  (default `as: "form"`) and LV raises `Duplicate id found`. Pass
  distinct `as:` per form (`event_form`/`note_form`) and match the
  handle_event params shape accordingly.
- Magic-link sign-in (`:sign_in_with_magic_link`) runs
  `AssignFirstUserAdmin` and overrides whatever `role` was set on the
  user — so test login helpers that need a non-default role must
  call `:assign_role` (authorize?: false) **after** the magic-link
  POST and before the LV mounts, then reload the user. Setting role
  on `:register` first is not sufficient.
- `Accounts.User` has `users_one_admin_idx` (one admin per Postgres
  transaction). `ExUnitProperties` `check all` iterations share one
  transaction, so `create_user(:admin)` inside the property body fails
  on the second iteration. Mint the admin once in `setup` and pass via
  context; freshly mint only `:operator`/`:viewer` per iteration.
- AshOban triggers need `pagination keyset?: true, required?: false`
  on the `read_action`, plus `Oban, testing: :manual` in
  `config/test.exs` so `AshOban.Test.schedule_and_run_triggers/2` can
  drain queues against the sandbox. Side effect: `Oban.config().queues`
  is `[]` — assert on `Application.get_env(:…, Oban)[:queues]`.
- Helpers used in both `data-*={…}` and `:if={…}` must return booleans —
  string `"false"` is truthy, so `:if` always passes. Convert at the
  attribute boundary with `to_string/1`.
- `validate(attribute_in(:field, list))` rejects `nil` even when `allow_nil?(true)`; for optional enum-like strings (e.g. Persona `model_override`), guard nil in a custom `change/2` validation before membership checks.
- Running multiple `mix test` commands concurrently in the same checkout can corrupt BEAM artifacts under `_build` (e.g., `Inspect` load errors); run compile/test serially per worktree.
## 11. When in Doubt

1. Check `specs/decisions/` for existing ADRs
2. If decision needed, propose new ADR before coding
3. Never invent business logic — refer to spec or ask
4. Ash patterns: https://hexdocs.pm/ash
5. Deployment-specific compliance: `specs/compliance/` (deployer fills)

## 12. After Each Task

1. Run `just verify`
2. Commit with `[<phase>.<story>] description`
3. Update `STATUS` in story
4. If something learned, append to "Gotchas" (or PR a research note)
5. If architectural decision made, create ADR

---

**Format**: AGENTS.md (Linux Foundation / Agentic AI Foundation standard)
**See also**: `README.md` (humans), `BASELINE.md` (decisions),
`docs/first-week-plan.md` (start here)
