# Getting Started

> For first-time setup. After this, use `just <command>` for everything.

## Prerequisites

- macOS, Linux, or WSL2 (Windows native untested)
- Docker Desktop or Docker Engine
- Git
- `asdf` (recommended) or matching Elixir/Erlang/Node versions
- `just` task runner: `brew install just` or `apt install just`

## Clone

```bash
git clone https://github.com/slowdoctor-dev/ashy-walnut-desk
cd ashy-walnut-desk
```

## Install runtimes

```bash
# If using asdf:
asdf install   # installs from .tool-versions

# If not using asdf, install manually:
# - Elixir 1.17.3-otp-27
# - Erlang/OTP 27.1.2
# - Node.js 20.18.0
```

## Environment

```bash
cp .env.example .env
```

Fill in at minimum:
- `SECRET_KEY_BASE`: run `mix phx.gen.secret` after `mix deps.get`
- `ANTHROPIC_API_KEY`: your key
- `IDENTIFIER_HASH_SALT`: random hex, e.g., `openssl rand -hex 32`

## Database

```bash
# Start postgres + pgvector
docker compose up -d

# Wait for it to be ready, then:
mix deps.get
mix ecto.setup   # create + migrate + seed
```

## Run

```bash
# Interactive (recommended for dev)
iex -S mix phx.server

# Or plain:
just dev
```

Visit http://localhost:4000.

## Verify

```bash
just verify
```

Should pass: format check, credo lint, tests, spec check.

## What next

If you're new:
- Read [`BASELINE.md`](../BASELINE.md) — what the project is
- Read [`docs/methodology.md`](methodology.md) — how we develop
- Read [`docs/first-week-plan.md`](first-week-plan.md) — Day 1-7 plan

If you want to contribute:
- Read [`CONTRIBUTING.md`](../CONTRIBUTING.md)
- Pick a story from `specs/phase-N/stories/`
- Follow `prompts/gsd-execute-story.md`

If you want to start fresh (Phase 0 from scratch):
- This scaffold has Phase 0 requirements drafted
- Day 2: BMAD Architect → `specs/phase-0/architecture.md`
- Day 3: BMAD PM → generate stories 0.2 through 0.M
- Day 4+: GSD → implement stories

## Troubleshooting

### Docker postgres won't start
- Check port 5432 isn't in use: `lsof -i :5432`
- Reset volumes: `just clean && docker compose up -d`

### Elixir compile errors
- Wrong version? `asdf current` should match `.tool-versions`
- Missing deps? `mix deps.clean --all && mix deps.get`

### pgvector extension missing
- Make sure `docker-compose.yml` uses `pgvector/pgvector:pg16` image
- Connect to DB and run: `CREATE EXTENSION IF NOT EXISTS vector;`

### LiveView 404 on /
- Have you run `mix ecto.setup`?
- Welcome LiveView is created in story 0.X (check phase-0 stories)

## Asking for help

- Bug? Open a GitHub issue
- Spec confusion? Open a discussion or PR clarifying the spec
- Security? See [`SECURITY.md`](../SECURITY.md) (do NOT use public issue)
