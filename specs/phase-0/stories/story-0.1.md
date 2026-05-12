# Story 0.1: Initialize Phoenix project + Ash dependencies

**Phase**: 0
**Estimate**: 2h
**Depends on**: — (first story)
**Status**: done

---

## Goal

Create a runnable Phoenix project with Ash 3.0 dependencies installed,
PostgreSQL via Docker Compose, and CI passing on initial commit.

## Context

This is the first story. Everything else in Phase 0 builds on this.
End state: `just dev` starts a server, even if it just shows the default
Phoenix welcome page.

## Reference specs

- `/AGENTS.md` § 4 (Stack), § 5 (Commands)
- `/BASELINE.md` § 5 (Stack)
- `/specs/architecture.md` § 6 (Technology stack), § 7 (Module layout)
- `/specs/phase-0/requirements.md` § 2 (Acceptance criteria)

## Acceptance criteria

- [x] AC1: Phoenix project generated with `mix phx.new ashy_walnut_desk --binary-id --no-mailer`
  Verify: `ls mix.exs lib/ashy_walnut_desk` exist
- [x] AC2: `.tool-versions` pins Elixir 1.17.3-otp-27, Erlang 27.1.2, Node 20.18.0
  Verify: `cat .tool-versions` matches
- [x] AC3: Ash 3.0 + ash_postgres + ash_phoenix + ash_authentication + ash_oban + ash_paper_trail dependencies in `mix.exs`
  Verify: `mix deps.get` succeeds; `grep ash mix.exs` shows all six
- [x] AC4: Docker Compose with PostgreSQL 16 + pgvector extension
  Verify: `docker compose up -d && docker compose exec db psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS vector; SELECT extversion FROM pg_extension WHERE extname='vector';"` returns a version
- [x] AC5: `mix phx.server` starts; visiting `http://localhost:4000` returns 200
  Verify: `curl -sf http://localhost:4000 -o /dev/null && echo OK`
- [x] AC6: `just verify` (format + credo + test + spec-check) passes on initial code
  Verify: `just verify` exits 0

## Files to create

```
mix.exs                                    — Phoenix project config + Ash deps
.tool-versions                             — asdf version pins
docker-compose.yml                         — postgres + pgvector
.env.example                               — env template
.gitignore                                 — Phoenix defaults + .env
.formatter.exs                             — include Ash, Phoenix, Ecto
.credo.exs                                 — Credo config (strict mode)
lib/ashy_walnut_desk/                      — app modules (generated)
lib/ashy_walnut_desk_web/                  — web modules (generated)
test/                                      — test files (generated)
config/{config,dev,test,runtime,prod}.exs  — Phoenix configs (generated)
```

## Files to modify

— (none, all files are new in this story)

## Implementation notes

1. Run `mix phx.new ashy_walnut_desk --binary-id --no-mailer` in parent dir,
   then move generated files into repo root.
   - `--binary-id`: required for Ash (UUIDs)
   - `--no-mailer`: defer mailer setup; magic-link auth in story 0.2 handles it
2. Add Ash dependencies in `mix.exs`:
   ```elixir
   {:ash, "~> 3.0"},
   {:ash_postgres, "~> 2.0"},
   {:ash_phoenix, "~> 2.0"},
   {:ash_authentication, "~> 4.0"},
   {:ash_authentication_phoenix, "~> 2.0"},
   {:ash_oban, "~> 0.2"},
   {:ash_paper_trail, "~> 0.4"},
   {:oban, "~> 2.18"},
   {:req, "~> 0.5"},
   ```
3. Docker Compose `db` service uses `pgvector/pgvector:pg16` image.
4. Do NOT yet run `mix ash_authentication.install` — that's story 0.2.
5. Do NOT yet create any Resource — that's story 0.3+.

## Safety review

- Sensitive records touched? **No** — foundational only
- AI output to end user possible? **No**
- Guardrails applied? **N/A**
- Audit trail covered? **N/A** (AshPaperTrail configured in story 0.4)

## Out of scope (will NOT do in this story)

- AshAuthentication installation → story 0.2
- AshPaperTrail configuration → story 0.4
- First Resource (User) → story 0.5
- GitHub Actions CI workflow → story 0.6 (or per Architect)
- gettext additional locales → later story
- LiveView welcome page customization → later story

## Verification

```bash
# After implementation:
docker compose up -d
mix deps.get
mix ecto.setup
just verify

# Should output:
# ✓ All verification gates passed

# Plus story-specific:
curl -sf http://localhost:4000 -o /dev/null && echo "OK: server responds"
docker compose exec db psql -U postgres -c "SELECT extversion FROM pg_extension WHERE extname='vector';" \
  | grep -q '^ 0\.\|^ 1\.' && echo "OK: pgvector installed"
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
  - Generated Phoenix scaffold in `/tmp` and merged into repo root to preserve existing docs/spec files.
  - Kept auth installation out of scope (no `mix ash_authentication.install`), consistent with story notes.
- Spec drift noticed:
  - `ash_authentication_phoenix` (2.12.0) is currently not compilable in this stack baseline because it injects
    `:phoenix_live_view` as a custom compiler, which requires `compile.phoenix_live_view`, but the task is absent
    in the current dependency set (`mix help compile.phoenix_live_view` fails and suggests `compile.phoenix`).
  - Workaround plan for story 0.2:
    1. Keep `ash_authentication_phoenix` out of the dependency list in 0.1.
    2. In 0.2, either pin to a version compatible with current Phoenix LiveView compiler tasks, or add the
       compatibility path recommended by upstream AshAuthentication Phoenix docs/changelog.
    3. Re-test via `mix deps.compile ash_authentication_phoenix --force` before integrating auth UI routes.
- Gotchas to add to AGENTS.md §10:
  - In this environment, some Mix/DB commands require escalated execution for localhost Docker DB access.
