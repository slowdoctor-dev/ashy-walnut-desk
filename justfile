# ashy-walnut-desk — task runner
#
# Install just: brew install just (or apt install just)
# Usage: just <command>
# List all: just

# Default: show available recipes
default:
    @just --list

# === Setup ===

# First-time setup
setup:
    @if [ ! -f .env ]; then cp .env.example .env && echo "✓ .env created — fill in API keys"; fi
    mix deps.get
    @echo ""
    @echo "Next: docker compose up -d && mix ecto.setup"
    @echo "Then: just dev"

# === Dev ===

# Start dev server
dev:
    iex -S mix phx.server

# Start dev server (non-interactive)
dev-bg:
    mix phx.server

# === Verification gates (MUST pass before commit) ===

# Run all verification gates
verify: format-check credo gettext-check test audit-verify spec-check
    @echo "✓ All verification gates passed"

# Format check
format-check:
    mix format --check-formatted

# Format (auto-fix)
format:
    mix format

# Credo lint
credo:
    mix credo --strict

# Re-extract gettext .pot from source and fail if the working tree drifts.
# Mirrors CI Gate 3b — keeps story-level just verify in lockstep with CI.
gettext-check:
    @mix gettext.extract >/dev/null
    @git diff --exit-code priv/gettext/ \
      || (echo "✗ gettext drift — run 'mix gettext.extract' locally and commit"; exit 1)

# All tests
test:
    mix test

# Verify audit chain integrity
audit-verify:
    mix audit.verify

# Test specific file
test-file FILE:
    mix test {{FILE}}

# Verify code matches /specs
spec-check:
    @./scripts/spec-check.sh

# Type check (slow)
dialyzer:
    mix dialyzer

# === Project status ===

# Show current phase, story, and blockers
status:
    @./scripts/status.sh

# === DB (Ash-managed) ===

# Generate migration from Ash resources
migrate-gen NAME:
    mix ash_postgres.generate_migrations --name {{NAME}}

# Run migrations
migrate:
    mix ecto.migrate

# Reset DB (drop, create, migrate, seed)
db-reset:
    mix ecto.reset

# === Phase 1 evidence ===

# Capture Identity timeline screenshots into docs/phase-1-screenshots/
# (requires `just dev` running in another terminal + python3 playwright)
screenshots:
    @./scripts/screenshots-phase1.sh

# Capture Inbox chain screenshots into docs/phase-2-screenshots/
# (requires `just dev` running in another terminal + python3 playwright)
phase2-screenshots:
    @./scripts/screenshots-phase2.sh

# Capture AuditLive + Compensation screenshots into docs/phase-3-screenshots/
# (requires `just dev` running in another terminal + python3 playwright)
phase3-screenshots:
    @./scripts/screenshots-phase3.sh

# Capture Phase 4/5 manuals + grounded-generation screenshots (needs `just dev` running)
phase5-screenshots:
    @./scripts/screenshots-phase5.sh

# === Story workflow ===

# Print prompt to start a new story execution session
story-prompt:
    @cat prompts/gsd-execute-story.md

# Print prompt to start phase planning (BMAD Analyst)
analyst-prompt:
    @cat prompts/bmad-analyst.md

# Print prompt to start architecture design (BMAD Architect)
architect-prompt:
    @cat prompts/bmad-architect.md

# Print prompt to start story breakdown (BMAD PM)
pm-prompt:
    @cat prompts/bmad-pm.md

# Print prompt for code review
review-prompt:
    @cat prompts/code-review.md

# === Cleanup ===

# Remove all containers, volumes (DESTRUCTIVE)
clean:
    docker compose down -v
    rm -rf _build deps node_modules

# Remove build artifacts only
clean-soft:
    rm -rf _build cover
