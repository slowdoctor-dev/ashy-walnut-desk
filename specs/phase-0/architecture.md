# Phase 0 — Architecture

> Drafted in two passes: §1–§3 by Codex (gpt-5.3-codex), §4–§12 by Claude
> after Codex hit its 5h usage limit on 2026-05-12. Pending Codex review
> when its quota refreshes. Approval flow per `prompts/bmad-architect.md`.

## 1. Overview

Phase 0 establishes the runnable Phoenix + Ash foundation without domain-axis
business resources. The application remains a single Phoenix application, not
an umbrella, because Phase 0 needs fast local setup, simple CI, and one deployable
unit. The project-level architecture still shapes the module layout so later
Identity, Interaction, Knowledge, AI, Safety, and worker modules can be added
without moving foundation code.

Resolution: single app over umbrella project. This keeps Phase 0 simple and
matches the single-instance Season 1 target, at the cost of less physical
separation between future subsystems.

```text
┌─────────────────────────────────────────────────────────────────┐
│                         Browser / Operator                       │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AshyWalnutDeskWeb.Endpoint                    │
│ Router, session, CSRF, LiveView socket, gettext                  │
└───────────────┬───────────────────────────────┬─────────────────┘
                │                               │
                ▼                               ▼
┌───────────────────────────────┐   ┌─────────────────────────────┐
│ WelcomeLive                   │   │ Auth LiveViews / Controllers │
│ /                             │   │ magic-link signup + login    │
│ project name + version        │   │ via AshAuthentication        │
└───────────────┬───────────────┘   └──────────────┬──────────────┘
                │                                  │
                ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AshyWalnutDesk.Accounts                       │
│ Ash.Domain for User, Token, Role/Auth support                    │
│ all account behavior through Ash actions and policies            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│ PostgreSQL 16                                                    │
│ app tables, AshAuthentication tables, AshPaperTrail config,      │
│ Oban jobs, pgvector extension, pg_trgm extension                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Background Runtime                                               │
│ Oban configured with queues: default, messages, ai, reindex      │
│ queues exist now; domain workers arrive in later phases          │
└─────────────────────────────────────────────────────────────────┘
```

Phase 0 creates these foundation areas:

- `AshyWalnutDesk.Application` starts Repo, PubSub, Endpoint, Oban, and other
  normal Phoenix supervision children.
- `AshyWalnutDesk.Repo` is the Ash/Postgres-backed repository.
- `AshyWalnutDesk.Accounts` is the only Phase 0 Ash domain.
- `AshyWalnutDesk.Accounts.User` supports magic-link authentication and the
  minimal role model needed for first-user admin behavior.
- `AshyWalnutDeskWeb` provides the router, gettext-backed UI, auth routes, and
  a minimal welcome LiveView.
- Database setup enables `pgvector` and `pg_trgm` now even though embeddings
  and fuzzy/domain search are deferred to later phases.
- Oban queues are configured now even though `messages`, `ai`, and `reindex`
  workers are deferred to later phases.
- `AshPaperTrail` is installed/configured now; account resources that carry
  sensitive identity data opt into audit behavior as applicable.

Phase 0 deliberately does not create Identity, Interaction, Knowledge, AI draft,
Safety validator, channel adapter, RAG, or deployment-specific compliance
resources. Those remain phase-scoped additions.

Key decision captured here: **single app, not umbrella**.

## 2. Affected modules

Phase 0 targets the Phoenix scaffold, account/auth foundation, database runtime,
and developer workflow files. The module list is intentionally foundation-only;
axis-specific modules are reserved for later phases.

### Application/runtime

- `lib/ashy_walnut_desk/application.ex` — OTP application supervisor; starts
  Telemetry, Repo, PubSub, Endpoint, Oban, and any standard Phoenix children.
- `lib/ashy_walnut_desk/repo.ex` — Ecto repo used by AshPostgres resources and
  Oban.
- `lib/ashy_walnut_desk.ex` — application boundary module for shared app-level
  helpers, kept minimal in Phase 0.

### Accounts/authentication

- `lib/ashy_walnut_desk/accounts.ex` — Ash domain for account resources.
- `lib/ashy_walnut_desk/accounts/user.ex` — authenticated operator account;
  magic-link sign-in; first-user admin role assignment.
- `lib/ashy_walnut_desk/accounts/token.ex` — AshAuthentication token resource
  for magic-link authentication.
- `lib/ashy_walnut_desk/accounts/changes/assign_first_user_admin.ex` — Ash
  change that grants `admin` to the first registered user and `operator` to
  subsequent users.
- `lib/ashy_walnut_desk/accounts/policies.ex` or inline resource policies —
  account authorization rules. Use inline policies if the generated Ash style
  is clearer after scaffold creation.

Resolution: AshAuthentication uses magic-link only in Phase 0. Password auth is
deferred because the requirements call for no passwords initially, and adding
password flows now increases account-surface area without improving the Phase 0
acceptance criteria.

Resolution: the initial admin user is created through signup. The first
successfully registered user receives the `admin` role via an Ash change. This
keeps setup self-service, avoids committing credentials or seed secrets, and
requires tests to lock the first-user behavior.

### Web modules

- `lib/ashy_walnut_desk_web.ex` — standard Phoenix web interface definitions.
- `lib/ashy_walnut_desk_web/endpoint.ex` — Phoenix endpoint, LiveView socket,
  session, and static asset configuration.
- `lib/ashy_walnut_desk_web/router.ex` — browser pipeline, auth routes, and
  authenticated/unauthenticated route scopes.
- `lib/ashy_walnut_desk_web/gettext.ex` — gettext backend.
- `lib/ashy_walnut_desk_web/live/welcome_live.ex` — root LiveView showing
  project name and version with gettext-backed strings.
- `lib/ashy_walnut_desk_web/live/auth_live/*` or generated
  AshAuthentication Phoenix modules — magic-link request/sign-in screens,
  following AshAuthentication Phoenix conventions.
- `lib/ashy_walnut_desk_web/components/core_components.ex` — generated Phoenix
  components, kept close to scaffold defaults unless auth or welcome UI needs
  small additions.
- `lib/ashy_walnut_desk_web/controllers/page_controller.ex` —
  include only if Phoenix generator creates it; prefer `WelcomeLive` for `/`.

### Configuration

- `config/config.exs` — shared Phoenix, Ash, gettext, and Oban configuration.
- `config/dev.exs` — local endpoint, database, Swoosh local mailbox, and watcher
  config.
- `config/test.exs` — sandboxed test database, disabled server, test mailer.
- `config/runtime.exs` — runtime env loading for database URL, secret key base,
  and future deployment settings.
- `config/prod.exs` — production-safe defaults without checked-in secrets.

### Database/migrations

- `priv/repo/migrations/*` — generated AshPostgres migrations for accounts,
  tokens, Oban, extensions, and any PaperTrail support tables required by the
  selected AshPaperTrail setup.
- `priv/repo/resource_snapshots/*` — AshPostgres resource snapshots generated
  alongside migrations.
- `priv/repo/seeds.exs` — no admin credentials seeded. Keep only harmless local
  development seed hooks if needed.
- `priv/gettext/*` — gettext POT/PO files for Phase 0 user-facing strings.

### Developer workflow and CI

- `mix.exs` — Phoenix, Ash, AshAuthentication, AshPostgres, AshPhoenix,
  AshPaperTrail, Oban, Swoosh, Credo, and test dependencies.
- `mix.lock` — pinned dependency resolution.
- `.tool-versions` — Elixir, Erlang/OTP, and Node versions matching the baseline.
- `docker-compose.yml` — PostgreSQL 16 service with pgvector and pg_trgm support.
- `justfile` — `setup`, `dev`, `verify`, `spec-check`, and BMAD prompt commands.
- `.github/workflows/ci.yml` — GitHub-hosted CI running format, credo, tests,
  and spec-check.
- `README.md` — quick-start that matches the actual commands.
- `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md` — documentation foundation.
- `scripts/spec-check.sh` and `scripts/status.sh` — lightweight spec/status
  checks used by `just`.

Resolution: CI uses GitHub-hosted runners. That matches the public OSS repo,
keeps maintainer infrastructure minimal, and is sufficient for Phase 0. A
self-hosted runner can be reconsidered only if later phases introduce private
services or runner-specific constraints.

### Assets

- `assets/` — Phoenix-generated asset pipeline.
- `assets/css/app.css` — Tailwind entrypoint produced by the Phoenix generator.
- `assets/js/app.js` — Phoenix LiveView client entrypoint.

Resolution: use the Tailwind version installed by the selected Phoenix 1.7
generator. Do not force a Tailwind major version in the architecture unless the
generator/dependency set requires it. This avoids fighting Phoenix defaults
during scaffold setup.

§2 records four more open-question resolutions: magic-link only, first signup
becomes admin, GitHub-hosted CI, and Phoenix-generator Tailwind default.

## 3. Ash resources

Phase 0 creates only account/auth resources. No Identity, Interaction,
Knowledge, AI, Safety, or deployment compliance resources are introduced.

### `AshyWalnutDesk.Accounts.User`

Purpose: operator account for humans using the desk.

Attributes:

| Name | Type | Sensitive? | Notes |
|---|---|---:|---|
| `id` | `:uuid` | no | Primary key. |
| `email` | `:ci_string` | yes | Login identifier. Required. Unique. |
| `email_hash` | `:string` | yes | SHA-256 hash of normalized email, used for lookup/audit-safe correlation where possible. |
| `role` | `:atom` or `:string` enum | no | `:admin` or `:operator`; first registered user becomes `admin`. |
| `confirmed_at` | `:utc_datetime_usec` | no | Set when magic-link authentication confirms the address. |
| `last_signed_in_at` | `:utc_datetime_usec` | no | Updated after successful sign-in if supported cleanly by AshAuthentication hooks. |
| `created_at` | `:utc_datetime_usec` | no | Generated timestamp. |
| `updated_at` | `:utc_datetime_usec` | no | Generated timestamp. |

Relationships:

| Relationship | Target | Notes |
|---|---|---|
| `has_many :tokens` | `AshyWalnutDesk.Accounts.Token` | Authentication tokens owned by the user. |

Actions:

| Action | Type | Purpose |
|---|---|---|
| `register_with_magic_link` | create | Create or initiate a user registration via magic-link flow. |
| `request_magic_link` | read/action | Request a sign-in link for an existing or new email, following AshAuthentication conventions. |
| `sign_in_with_magic_link` | action | Validate token and establish authenticated session. |
| `assign_role` | update | Admin-only role change for future account management. |
| `mark_signed_in` | update | Record successful sign-in timestamp when practical. |
| `read` | read | Policy-restricted user lookup. |

Policies:

| Actor | Allowed |
|---|---|
| Unauthenticated visitor | May request a magic link and complete magic-link sign-in. |
| Self | May read limited own account data. |
| Admin | May read users and assign roles. |
| Operator | May read limited own account data only. |
| System | May perform authentication token and timestamp updates needed by auth flow. |

Extensions/configuration:

- `AshAuthentication` with magic-link strategy only.
- `AshPostgres` data layer.
- `AshPaperTrail` enabled if compatible with the auth resource shape in Phase 0;
  at minimum, account state transitions must be auditable before any sensitive
  account changes are accepted as complete.
- Policies are required; no public-by-default resource access.
- `email` is marked `sensitive? true`.
- `email_hash` is generated from normalized email before storage.

Implementation note: if AshAuthentication's generated resource shape uses
different action names, keep the generated internals but expose/document the
intent above in the architecture and tests. Do not bypass Ash actions with direct
Repo calls.

### `AshyWalnutDesk.Accounts.Token`

Purpose: token storage for magic-link authentication.

Attributes:

| Name | Type | Sensitive? | Notes |
|---|---|---:|---|
| `id` | `:uuid` or generated token key | yes | Token identifier, following AshAuthentication defaults. |
| `token` | `:binary` or `:string` | yes | Hashed token material if supported by the strategy; raw token must not be logged. |
| `purpose` | `:string` | no | Magic-link purpose/context. |
| `expires_at` | `:utc_datetime_usec` | no | Expiration timestamp. |
| `created_at` | `:utc_datetime_usec` | no | Generated timestamp. |

Relationships:

| Relationship | Target | Notes |
|---|---|---|
| `belongs_to :user` | `AshyWalnutDesk.Accounts.User` | Token owner, when the selected AshAuthentication strategy models ownership directly. |

Actions:

| Action | Type | Purpose |
|---|---|---|
| generated token actions | create/read/destroy | Use AshAuthentication token-resource defaults. |

Policies:

| Actor | Allowed |
|---|---|
| Public | No direct token reads. |
| System/auth flow | May create, validate, and revoke tokens. |
| Admin/operator | No direct token access through UI. |

Extensions/configuration:

- `AshAuthentication.TokenResource`.
- `AshPostgres` data layer.
- Token fields are sensitive where supported.
- Token cleanup can be handled later by Oban if generated defaults do not include
  cleanup in Phase 0.

### No Phase 0 domain-axis resources

The following are explicitly deferred:

- Identity axis: `Identity`, `Event`, `Appointment`, `FollowUp`, `Note`,
  `Consent`.
- Interaction axis: `Conversation`, `Message`, `Channel`, `Draft`, `Template`.
- Knowledge axis: `Manual`, `Guardrail`, `Persona`, `Vault`.
- AI/Safety resources: prompt logs, validator outputs, AI drafts.

This keeps Phase 0 limited to foundation acceptance criteria and avoids inventing
business logic before Phase 1+ specs exist.

## 4. LiveView components

Phase 0 ships exactly the LiveViews required by the acceptance criteria
(welcome page + magic-link flow). Inbox, Overview, Identity, and Knowledge
LiveViews are explicitly deferred to their respective phases. The
project-level layout under `lib/ashy_walnut_desk_web/live/` already reserves
their directories (see `specs/architecture.md §7`); Phase 0 does not create
those directories.

### `AshyWalnutDeskWeb.WelcomeLive`

- **Route**: `GET /` — public, no auth required.
- **Mount data**: application name (compile-time constant), version (read from
  `Application.spec(:ashy_walnut_desk, :vsn)`), authenticated-user summary if a
  session is present (else a "Sign in" link).
- **Events handled**: none — render-only. Sign-in is a link to the
  AshAuthentication route, not an in-LiveView event.
- **Components used**: scaffold-generated layout + `core_components.ex`. No
  custom components in Phase 0.
- **gettext**: project name is a constant; user-facing strings ("Welcome",
  "Sign in", "Version") flow through `gettext/1`.

### AshAuthentication Phoenix components

The architect defers magic-link request/confirm UI to AshAuthentication's
generated Phoenix components (`AshAuthentication.Phoenix.Router` macros and
default views). Phase 0 does not customize the look beyond what
`mix ash_authentication_phoenix.install` produces, except to apply gettext to
any user-visible strings the generator exposes for translation.

Routes contributed by the generator (typical names; verify post-install):

- `GET /sign-in` — request magic link form.
- `GET /auth/user/magic_link/:token` — confirm magic link.
- `POST /sign-out` — terminate session.

### Deferred LiveViews (NOT in Phase 0)

| LiveView | Phase |
|---|---|
| `inbox_live/*` | Phase 2 |
| `identity_live/*` | Phase 1 |
| `knowledge_live/*` | Phase 5 |
| `overview_live/*` | Phase 5 (depends on cross-axis data) |
| `components/countdown_send_button.ex` | Phase 4 |

Resolution: Phase 0 LiveView surface is one custom LiveView plus the
AshAuthentication-generated screens. Nothing more is required by the phase
acceptance criteria, so nothing more is built.

## 5. External integrations

Phase 0 has **no live external integrations**. The framework reserves
configuration slots that later phases will populate; it does not call any
external API.

### LLM provider — Anthropic (deferred)

- Configuration slot only: `ANTHROPIC_API_KEY` is read in
  `config/runtime.exs` and passed via application env. Absent value is
  acceptable in Phase 0; startup must not fail when the key is empty.
- No `AshyWalnutDesk.AI.*` modules are created in Phase 0.
- Active integration arrives in Phase 4 (per `BASELINE.md §7`).

### Channel adapters (deferred)

- No adapters in Phase 0 (per `BASELINE.md §7` — Phase 3 introduces the first
  channel).
- `lib/ashy_walnut_desk/interaction/adapters/` is not created.

### Email transport (magic-link delivery)

- **Dev**: Swoosh local mailbox (in-memory) — visible at
  `http://localhost:4000/dev/mailbox` per Phoenix defaults.
- **Test**: Swoosh test adapter — messages captured in-process for assertions.
- **Prod**: deployer-supplied SMTP via runtime env. Phase 0 does not ship a
  prod-grade mailer; production deployment is Phase 5+. `mix phx.new --no-mailer`
  is used by Story 0.1 per the story spec, so the mailer adapter is added later
  in Phase 0 (during the AshAuthentication install story).

### PostgreSQL (internal)

- Not external, but worth noting: extensions `pgvector` and `pg_trgm` are
  enabled by an early migration even though no Phase 0 resource uses them. The
  cost is one schema-setup migration; the benefit is removing an extension
  install from later phases' critical path.

## 6. Data flow

The two flows below are the only data movements in Phase 0. Each is a
sequence diagram in ASCII; both terminate cleanly with no AI, no outbound
messaging, no audit-trail-required state transitions beyond auth events.

### 6.1 Magic-link signup and sign-in

```text
Browser              Router/Endpoint     AshAuthentication       Accounts.User      Mailer (Swoosh)
   │                       │                    │                      │                  │
   │ GET /sign-in          │                    │                      │                  │
   ├──────────────────────▶│                    │                      │                  │
   │ form (gettext)        │                    │                      │                  │
   │◀──────────────────────┤                    │                      │                  │
   │                       │                    │                      │                  │
   │ POST email            │                    │                      │                  │
   ├──────────────────────▶│ request_magic_link │                      │                  │
   │                       ├───────────────────▶│ find_or_create user  │                  │
   │                       │                    ├─────────────────────▶│                  │
   │                       │                    │                      │                  │
   │                       │                    │ generate token (hashed in storage)      │
   │                       │                    ├──────────────────────┐                  │
   │                       │                    │                      ▼                  │
   │                       │                    │              Token (Accounts.Token)     │
   │                       │                    │                      │                  │
   │                       │                    │ deliver token URL    │                  │
   │                       │                    ├─────────────────────────────────────────▶│
   │ "check your email"    │                    │                      │                  │
   │◀──────────────────────┤                    │                      │                  │
   │                       │                    │                      │                  │
   │ clicks magic link     │                    │                      │                  │
   ├──────────────────────▶│ /auth/.../:token   │                      │                  │
   │                       ├───────────────────▶│ sign_in_with_magic_link                 │
   │                       │                    ├─────────────────────▶│ confirmed_at +    │
   │                       │                    │                      │ first-user check  │
   │                       │                    │                      │ → assign :admin   │
   │                       │                    │                      │   or :operator    │
   │                       │                    │ session established  │                  │
   │ 302 → /               │                    │                      │                  │
   │◀──────────────────────┤                    │                      │                  │
```

Notes:

- The "first-user check" runs inside the Ash create-or-update path using
  `AshyWalnutDesk.Accounts.Changes.AssignFirstUserAdmin` (§2). To prevent two
  concurrent signups both being assigned `:admin`, the change relies on a
  PostgreSQL serializable check or a unique partial index that admits at most
  one `admin` row (see §8.2). Detailed implementation choice deferred to the
  story that introduces the User resource; the architecture pins the invariant.
- Tokens stored hashed where the AshAuthentication strategy supports it; raw
  token only appears in the outbound email URL.

### 6.2 Welcome page render

```text
Browser → Router → WelcomeLive.mount/3 → render
                     │
                     ├─ app name (constant)
                     ├─ version: Application.spec(:ashy_walnut_desk, :vsn)
                     └─ if current_user: name + sign-out link
                        else: sign-in link
```

`mount/3` runs twice (HTTP + WebSocket) per AGENTS.md §10 — both invocations
must be side-effect-free. WelcomeLive reads only from compile-time constants and
the session; no DB writes.

## 7. Migration plan

### Authoring

- All migrations are generated by `mix ash_postgres.generate_migrations --name <desc>`
  per AGENTS.md §5. `mix ecto.gen.migration` is forbidden.
- Each `ash_postgres.generate_migrations` run also writes a matching snapshot in
  `priv/repo/resource_snapshots/` — these are committed alongside the migration.

### Phase 0 migration order

1. **`<ts>_enable_extensions.exs`** — `CREATE EXTENSION IF NOT EXISTS vector;
   CREATE EXTENSION IF NOT EXISTS pg_trgm;`. Hand-edited setup migration that
   runs before any resource migration (Ash supports custom extension migrations
   via `AshPostgres.Extensions` or a plain Ecto migration in this slot).
2. **AshAuthentication tables** — generated when the auth strategy is installed
   (`User`, `Token`).
3. **AshPaperTrail support tables** — generated when AshPaperTrail is enabled,
   even if no resource currently opts in.
4. **Oban migrations** — `Oban.Migration.up(version: <n>)` invoked from a
   generated migration.

### Rollback

- Each migration must implement both `up/0` and `down/0`. AshPostgres-generated
  migrations do this automatically.
- The extension-enable migration's `down` may leave extensions in place (drop
  is dangerous on a shared cluster). The migration is idempotent; rollback in
  Phase 0 is acceptable as a no-op for extension drops, documented in the
  migration's `down/0` comment.
- Snapshot files are also reverted by `mix ash_postgres.rollback`-style flows;
  if a snapshot is out of sync with the schema, regenerate snapshots from a
  clean database to recover.

### CI behaviour

- CI runs `mix ecto.create && mix ecto.migrate` against a fresh test database
  on every push. A drift between resource snapshots and the schema is a CI
  failure, caught by `mix ash_postgres.generate_migrations --check`.

## 8. Failure modes

Phase 0 surfaces a small number of failure modes. The project-level
`specs/architecture.md §10` lists framework-wide degradation modes (LLM down,
channel down, etc.) — none of those apply yet because none of those integrations
exist in Phase 0.

| # | Failure | Detection | Degradation / handling |
|---|---|---|---|
| 8.1 | PostgreSQL down at startup | OTP supervisor fails to start `Repo` | Application fails to boot; meta-ops alert. Acceptable for Phase 0 (no graceful-mode requirement). |
| 8.2 | Two concurrent signups racing for first-admin | Partial-unique constraint on `role = 'admin'` rejects the second insert | Loser is created as `:operator`. Manual promotion via `assign_role` action later. Story-level test covers the race. |
| 8.3 | Magic-link email delivery fails | Swoosh dev mailbox always succeeds; prod SMTP not in Phase 0 | Out of scope this phase. Documented as Phase 5 production-readiness work. |
| 8.4 | Expired magic-link token presented | AshAuthentication rejects on `expires_at` check | User sees "link expired" — re-request flow available. Standard generator behavior. |
| 8.5 | Token replay attempt | Token marked consumed/revoked on first successful use (AshAuthentication default) | Second use rejected; logged via PaperTrail if the resource opts in. |
| 8.6 | gettext missing translation | falls back to msgid (English source) per Phoenix default | Acceptable. Deployer's locale story is Phase 5. |
| 8.7 | Oban queue starvation | N/A in Phase 0 — no domain workers enqueue jobs | Health-check covered when workers arrive. |
| 8.8 | LiveView WebSocket reconnect | Phoenix LiveView built-in | Default; WelcomeLive idempotent so reconnect is safe (per AGENTS.md §10 `mount/3` runs twice). |

Decision: Phase 0 does **not** add custom failure-handling infrastructure
(circuit breakers, dead-letter queues, retry policies) because no Phase 0 path
warrants it. Each later phase adds its own as the corresponding integration
arrives.

## 9. Security considerations

Phase 0 security is the foundation; later phases add domain-specific controls
on top of it.

### Authentication and authorization

- All routes are explicitly classified in the router as `:browser` (public,
  CSRF-protected) or `:browser_authenticated` (additionally requires session
  user). No "default-allow" pipelines.
- AshAuthentication issues session cookies via `Plug.Session`. Cookies are
  signed, `secure` in prod, `http_only`, `same_site: "Lax"`.
- All Ash actions on User and Token are policy-gated (§3). No public-by-default
  resource access.
- Ash actor is set on every authenticated controller/LiveView mount; actions
  called without an actor outside the auth bootstrap path fail closed.

### Sensitive data

- `email` marked `sensitive? true` — Ash redacts it from `inspect/1` output and
  generated logs.
- `email_hash` (SHA-256 of normalized email) supports lookup and log correlation
  without exposing the raw value. The hash salt is `IDENTIFIER_HASH_SALT`
  loaded from runtime env (already provisioned in `.env`).
- Magic-link tokens stored hashed where the AshAuthentication strategy supports
  it; the raw token only appears in the email URL during the brief delivery
  window.
- Phase 0 stores no client/customer data — there are no Identity resources yet.
  All sensitive data in Phase 0 is operator-account data only.

### Secrets

- All secrets via env vars; `.env` is gitignored and never committed.
- `config/prod.exs` contains no secret defaults; all secrets read from
  `config/runtime.exs`.
- `SECRET_KEY_BASE` and `IDENTIFIER_HASH_SALT` were generated and stored in
  `.env` during Day 1.

### Transport and network

- Phoenix endpoint binds `127.0.0.1` in dev. Production binding is a deployer
  concern (Phase 5).
- TLS termination is at the deployment edge (Cloudflare Tunnel per
  `BASELINE.md §12`); not configured in this phase.
- Webhook endpoints do not exist in Phase 0 (no channels); signature
  verification arrives with the channel adapter in Phase 3.

### Audit

- AshPaperTrail is installed and configured at the app level. In Phase 0 the
  only resource potentially opting in is `User` (auth events). If
  AshPaperTrail integration with the generated AshAuthentication shape requires
  refactoring at this stage, deferring `User`-level audit to Phase 1 is
  acceptable — the framework-level capability is the Phase 0 deliverable.

### Out of scope for Phase 0 (and the corresponding NEVER from AGENTS.md §9)

- AI prompt/response logging — no AI in Phase 0.
- Send approval, countdown, disclosure — no outbound messages in Phase 0.
- Cross-border data transfer policy — deployer concern (`specs/compliance/`).

## 10. Safety review

Per `prompts/bmad-architect.md`, this section applies AGENTS.md §7
(INVIOLABLE rules) to the phase.

### Sensitive data flow

- Operator `email` and `email_hash` flow from the magic-link form into
  Accounts.User and into the magic-link email. Both attributes are `sensitive?
  true`; raw email is logged only via Phoenix request logs subject to the
  framework's parameter filter (which `:password` is the default filter for —
  we add `:email` to the filter list in `config/config.exs`).
- Magic-link tokens flow only over the link URL and into the Token resource
  (hashed at rest). Token values must never appear in process logs, Telemetry
  events, or PaperTrail diffs.

### Where AI output could reach an end user

- **Nowhere in Phase 0.** No AI client exists; no AI module is wired up. The
  `ANTHROPIC_API_KEY` slot is reserved but unused. This rules out §7 rule 1
  (no domain assertions in AI output) and §7 rule 5 (disclosure) for this
  phase by construction.

### Guardrails applied

- §7 rule 2 (human-in-the-loop for sends): **N/A** — Phase 0 has no outbound
  message path. The only outbound traffic is the magic-link email, which is a
  system-generated transactional message, not an AI draft. No countdown
  required; ADR-013 applies only to messages-to-customers.
- §7 rule 3 (audit trail mandatory): Auth events route through Ash actions and
  thus are eligible for audit. The Phase 0 commitment is at the framework
  level (AshPaperTrail installed); per-resource audit on User may be deferred
  to Phase 1 if compatibility issues surface.
- §7 rule 4 (sensitive data handling): `email`, `email_hash`, `token` all
  marked sensitive. Raw values never logged in production.

### Audit trail coverage

- Migration history is its own audit trail (git + `priv/repo/migrations`).
- AshPaperTrail is configured even though no Phase 0 resource currently has it
  enabled, so the infrastructure exists when Phase 1 needs it.
- Sign-in success/failure events are emitted via Telemetry by AshAuthentication
  defaults; a structured-log handler is not added in Phase 0 (Phase 5 logging
  story).

### Inviolable-rules compliance summary

| AGENTS.md §7 rule | Phase 0 status |
|---|---|
| 1. No unvalidated AI domain assertions | N/A — no AI |
| 2. Human-in-the-loop for sends | N/A — no outbound customer messaging |
| 3. Audit trail mandatory | Framework installed (AshPaperTrail); per-resource opt-in deferred where needed |
| 4. Sensitive data handling | Email + email_hash + token sensitive; hash salt from env |
| 5. AI-assistance disclosure | N/A — no AI |

Phase 0 introduces no new inviolable-rule risk. Subsequent phases inherit the
framework-level controls and add their own per-axis safety modules.

## 11. Testing strategy

Test surface in Phase 0 is small. Each AC in `specs/phase-0/requirements.md
§2` maps to one or more tests below.

### Unit (`mix test`)

- `AshyWalnutDesk.Accounts.User`:
  - `register_with_magic_link` creates User with `email`, generates `email_hash`,
    leaves `confirmed_at` nil.
  - First successful sign-in assigns `:admin`; second assigns `:operator`
    (covers `Changes.AssignFirstUserAdmin`).
  - `assign_role` rejects non-admin actor (policy test).
  - `read` returns own record for `:operator`; admin sees all.
- `AshyWalnutDesk.Accounts.Token`:
  - Cannot read tokens without the system actor (policy test).
  - Token storage is hashed where the strategy supports it (introspection test).
- `IdentifierHash` helper (if extracted):
  - Same email → same hash; case + whitespace normalized.

### Integration (`Phoenix.LiveViewTest`)

- `WelcomeLive`:
  - Renders project name + version string for unauthenticated user.
  - Renders sign-in link when no session.
  - Renders user identifier + sign-out link when session present.
- Magic-link flow (LiveView + controller mix as the generator dictates):
  - Submit email → captured Swoosh email contains a token URL.
  - Visit token URL → session established, redirected to `/`.
  - Expired token → user sees an error and can re-request.
  - Replayed token → rejected.
- First-user race:
  - Two concurrent registrations (Task-based concurrency test) — exactly one
    ends up `:admin`.

### Property-based (`StreamData`)

- Deferred. Phase 0 has no domain invariants beyond auth, which is covered by
  scenario tests. Add property tests in Phase 1+ where Identity invariants
  begin to accumulate.

### Manual

- Visual: run `just dev`, visit `/`, confirm welcome page renders and the
  Swoosh dev mailbox receives the magic-link email.
- Visual: confirm AshAuthentication-generated UI is gettext-translatable
  (English msgids appear in `priv/gettext/en/LC_MESSAGES/default.po`).

### Spec-check (`scripts/spec-check.sh`)

- Verifies that every phase listed in `BASELINE.md §7` matches a
  `specs/phase-N/` directory where one exists.
- Verifies that every story file matches the `_template.md` skeleton.
- Verifies that every ADR is referenced from `BASELINE.md §6`.

### CI gates

`.github/workflows/ci.yml` runs, in order: `mix format --check`, `mix credo
--strict`, `mix ash_postgres.generate_migrations --check`, `mix test`,
`scripts/spec-check.sh`. Any non-zero exit fails the build.

### No real customer data

Per AGENTS.md §9: tests use fakers / generated emails only. Phase 0 has no
client/customer records anyway, so this is satisfied by construction.

## 12. Open technical questions

Resolved during sections §1–§3:

- ✅ Single Phoenix app vs umbrella → single app (§1).
- ✅ Magic-link only vs password too → magic-link only (§2, §3).
- ✅ Tailwind v3 vs v4 → whichever the Phoenix 1.7 generator installs (§2).
- ✅ CI runner → GitHub-hosted (§2).
- ✅ Initial admin → signup; first user becomes admin via Ash change (§2, §3).

Remaining for the PM persona / per-story discussion (none are blockers for
breaking Phase 0 into stories):

1. **AshPaperTrail on `User` in Phase 0 vs Phase 1.** Phase 0 commits to
   installing AshPaperTrail at the app level. Whether the `User` resource
   itself opts in this phase depends on a smooth integration with the
   AshAuthentication-generated resource shape. Decide during the
   AshAuthentication-install story.

2. **Production mailer.** Phase 0 uses Swoosh local mailbox in dev and the
   test adapter in test. A production SMTP adapter belongs to the deployer
   and to Phase 5 deployment work. Confirm during Phase 5 that no Phase 0
   code paths break when a real mailer is wired in.

3. **Healthcheck endpoint.** No Phase 0 AC requires `/healthz`. Defer to
   Phase 5 unless a CI / dev-loop pressure surfaces earlier. Adding it now
   would be premature.

4. **AshAdmin in Phase 0.** `AGENTS.md §4` lists `ash_admin` in the stack.
   No Phase 0 AC requires the admin UI, and exposing it without proper
   policy review introduces risk. Recommend: install the dependency only,
   do not mount the admin route until Phase 1 (Identity-axis resources need
   admin visibility before any operator does).

5. **Telemetry log handler.** Sign-in success/failure are emitted as
   Telemetry events by AshAuthentication. Phase 0 does not subscribe a
   structured-log handler. Decide in Phase 5 (production deployment) whether
   a `:logger`-based handler or a dedicated meta-ops sink is the target.

---

Architecture at `/specs/phase-0/architecture.md`.
When approved, activate the PM persona to break into stories.
