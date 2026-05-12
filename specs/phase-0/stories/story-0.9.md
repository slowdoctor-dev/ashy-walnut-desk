# Story 0.9: GitHub Actions CI workflow

**Phase**: 0
**Estimate**: 1h
**Depends on**: 0.1
**Status**: done

---

## Goal

Add a GitHub Actions workflow that runs the Phase 0 verification gates on every push to `main` and on every pull request.

## Context

Phase 0 requirements §2 require "GitHub Actions CI green on push to `main`". Architecture §11 (Testing strategy — CI gates) specifies the gate order: `mix format --check` → `mix credo --strict` → `mix ash_postgres.generate_migrations --check` → `mix test` → `scripts/spec-check.sh`. Architecture §2 (Developer workflow and CI) commits to GitHub-hosted runners.

## Reference specs

- `/specs/phase-0/architecture.md` §11 (CI gates ordered list)
- `/specs/phase-0/architecture.md` §2 (Developer workflow and CI)

## Acceptance criteria

- [x] AC1: `.github/workflows/ci.yml` exists; triggers on `push: branches: [main]` and `pull_request:`. Verify: `cat .github/workflows/ci.yml | head -10` shows both triggers.
- [x] AC2: Workflow runs, in this order: `mix format --check`, `mix credo --strict`, `mix ash_postgres.generate_migrations --check`, `mix test`, `bash scripts/spec-check.sh`. Verify: reading the YAML, the five steps appear in that order.
- [x] AC3: Job uses Elixir + Erlang versions matching `.tool-versions` and a `pgvector/pgvector:pg16` PostgreSQL service container. Verify: workflow YAML references the versions and service image.
- [x] AC4: A push to a feature branch with a clean local `just verify` results in a green CI run. Verify: `gh run list --branch <feature> --limit 1 --json conclusion -q '.[0].conclusion'` returns `success`.

## Files to create

```
.github/workflows/ci.yml   — the CI workflow
```

## Files to modify

— (none)

## Implementation notes

- Use `erlef/setup-beam@v1` for the BEAM toolchain; pin `elixir-version` and `otp-version` to the values in `.tool-versions`.
- The `pgvector/pgvector:pg16` service container is needed because `mix ash_postgres.generate_migrations --check` and `mix test` both require the database to be up and the `vector` extension available.
- `IDENTIFIER_HASH_SALT` and `SECRET_KEY_BASE` for CI come from a dummy value set in the workflow `env:` (never from a real secret). Test fixtures don't need a strong salt; the salt only needs to be present and stable across the run.

## Safety review

N/A — CI configuration; no sensitive data flows. The dummy CI hash salt is non-production; document this in the workflow YAML so no operator confuses it with real config.

## Out of scope

- Deployment pipeline — Phase 5.
- Dependency vulnerability scanning (`mix sobelow`, `dialyzer`) — exists as `just security` / `just dialyzer` recipes but not gated in Phase 0 CI to keep the gate fast. Promote later if useful.
- Caching of `_build`/`deps` across runs — micro-optimization; revisit only if CI duration becomes a friction point.

## Verification

```bash
just verify   # local
git push origin <feature-branch>
gh run list --branch <feature-branch> --limit 1
gh run watch
```

## Notes during implementation

- Decisions made:
  - Used `erlef/setup-beam@v1` per implementation notes; versions
    pinned as strings (`"1.17.3"`, `"27.1.2"`) to match `.tool-versions`
    exactly.
  - Service container exposes Postgres on host `localhost:5432` and is
    created with `POSTGRES_DB: ashy_walnut_desk_test` so `mix ecto.create`
    is effectively a no-op in CI but still safe to call.
  - Inserted a "Prepare test database" step (`mix ecto.create` +
    `mix ecto.migrate`) between Gate 3 and Gate 4 so `mix test` has a
    migrated schema. The five required gates remain in spec order;
    setup steps don't count as gates.
  - Each gate step has a `Gate N — …` name prefix so a reviewer
    scrolling the CI log can confirm gate ordering at a glance.
- Spec drift noticed:
  - AC2 literally says `mix format --check`, but Mix 1.17 rejects that
    flag (the working invocation is `mix format --check-formatted`).
    Already learned during story 0.1's peer review (justfile fix); the
    story-0.9 spec text wasn't updated. CI uses the working flag.
- Gotchas to add to AGENTS.md §10:
  - None new — the three Phase-0 gotchas already in §10 cover what this
    story would have flagged (no test-env Oban, AshPostgres migration
    extension assumptions, etc.).
