# Phase 1 — Architecture

> Drafted by the BMAD Architect persona. Translates
> `specs/phase-1/requirements.md` into resource-level technical design.
> Approval flow per `prompts/bmad-architect.md`. Phase 0 architecture
> is the structural precedent.

## 1. Overview

Phase 1 builds the **Identity axis** (Who/When) on top of the Phase 0
foundation. Six new Ash resources land in a new `AshyWalnutDesk.Identity`
domain. The Accounts subsystem stays as the operator-actor surface; the
Identity domain holds customer records.

```text
                    ┌────────────────────────────────────────┐
                    │  Browser / Operator (admin/operator/   │
                    │                       viewer)          │
                    └───────────────────┬────────────────────┘
                                        │
                                        ▼
                    ┌────────────────────────────────────────┐
                    │     AshyWalnutDeskWeb.Endpoint         │
                    │     Router + LiveView socket           │
                    └───────────────────┬────────────────────┘
                                        │
                ┌───────────────────────┼──────────────────────┐
                ▼                       ▼                      ▼
       ┌─────────────────┐   ┌─────────────────┐   ┌───────────────────┐
       │ WelcomeLive (P0)│   │ IdentityLive.*  │   │ Auth (P0)         │
       └────────┬────────┘   │ Index / Show /  │   │ Sign in / out     │
                │            │ New / Edit      │   └─────────┬─────────┘
                │            └────────┬────────┘             │
                │                     │                      │
                │            ┌────────▼────────┐             │
                │            │ AshyWalnutDesk. │             │
                │            │ Identity        │             │
                │            │ (Ash.Domain)    │             │
                │            └────────┬────────┘             │
                │                     │                      │
                │   ┌─────────────────┼────────┐             │
                │   ▼      ▼          ▼        ▼   ▼   ▼     ▼
                │ Identity Event Appointment FollowUp Note Consent
                │   │      │          │        │   │   (ledger)
                │   │      │          │        │   │     │
                ▼   ▼      ▼          ▼        ▼   ▼     ▼
       ┌──────────────────────────────────────────────────────┐
       │                AshyWalnutDesk.Accounts (P0)          │
       │      User (admin/operator/viewer), Token, audit      │
       └──────────────────────────────────────────────────────┘
                                │
                                ▼
       ┌──────────────────────────────────────────────────────┐
       │                   PostgreSQL 16                      │
       │     6 new tables (with deleted_at on five of six)    │
       │     Consent is append-only, no deleted_at            │
       │     AshOban trigger nightly: Token expunge_expired   │
       └──────────────────────────────────────────────────────┘
```

Key shape decisions, with trade-offs:

- **Six resources, one domain.** All Identity-axis resources live in
  `AshyWalnutDesk.Identity`. Smaller domains are tempting but the records
  are deeply linked; splitting (e.g. scheduling sub-domain) creates
  cross-domain joins for the timeline view at no benefit.
- **Soft-delete on five of six** (Identity, Event, Appointment, FollowUp,
  Note). Consent is **append-only** — there's nothing to soft-delete; a
  "revoked" consent is a new row, not a state change on the old row.
  See ADR-019, ADR-020.
- **Three operator roles**: `:admin`, `:operator`, `:viewer`. `:viewer`
  is read-only; further partitioning deferred per requirements §3.
- **Identity timeline is a query, not a stored aggregation.** Each
  resource carries an `occurred_at` (or equivalent) timestamp; the
  timeline is a union ordered by that timestamp, paginated.
- **TO-3 resolved**: an AshOban trigger on `Accounts.Token` runs the
  `:expunge_expired` action nightly. Lives in the Token resource, not
  in this domain, but shipped as part of Phase 1.

## 2. Affected modules

### New (Identity domain)

- `lib/ashy_walnut_desk/identity.ex` — Ash.Domain registering all six
  Identity-axis resources.
- `lib/ashy_walnut_desk/identity/identity.ex` — customer record (the
  "Who"). Module name `AshyWalnutDesk.Identity.Identity` — the
  domain/resource naming collision is accepted to match the project
  architecture (`specs/architecture.md §2`).
- `lib/ashy_walnut_desk/identity/event.ex` — what happened
  (service rendered).
- `lib/ashy_walnut_desk/identity/appointment.ex` — scheduled future.
- `lib/ashy_walnut_desk/identity/follow_up.ex` — scheduled post-encounter.
- `lib/ashy_walnut_desk/identity/note.ex` — operator observation.
- `lib/ashy_walnut_desk/identity/consent.ex` — append-only consent ledger.
- `lib/ashy_walnut_desk/identity/changes/soft_delete.ex` — generic
  `Ash.Resource.Change` that sets `deleted_at` and prevents re-archiving.
- `lib/ashy_walnut_desk/identity/changes/hash_primary_identifier.ex` —
  before_action change that SHA-256-hashes the Identity's primary
  identifier on create/update.

### Modified (Accounts)

- `lib/ashy_walnut_desk/accounts/user.ex` — role enum gains `:viewer`;
  existing read/admin policies updated to admit `:viewer` for read paths
  added in Phase 1 (the User module's own policies don't change shape).
- `lib/ashy_walnut_desk/accounts/token.ex` — `oban do triggers do … end`
  block added; nightly trigger calls `:expunge_expired`.

### New (Web)

- `lib/ashy_walnut_desk_web/live/identity_live/index.ex` — paginated list
  of (non-archived) Identities.
- `lib/ashy_walnut_desk_web/live/identity_live/show.ex` — single Identity
  with timeline rendering.
- `lib/ashy_walnut_desk_web/live/identity_live/new.ex` — create form.
- `lib/ashy_walnut_desk_web/live/identity_live/edit.ex` — update form.
- `lib/ashy_walnut_desk_web/live/identity_live/timeline_component.ex` —
  the merged-chronological-view LiveComponent reused inside Show.
- Phase 1 doesn't ship a full CRUD UI for every related resource — the
  Show LiveView embeds inline create-event/create-appointment/create-note
  forms; full CRUD pages for Event/Appointment/etc. are out of scope
  unless the timeline test forces them.

### New (Migrations / config)

- `priv/repo/migrations/*_create_identity_*.exs` — generated by
  `mix ash_postgres.generate_migrations`. Multiple migrations, one per
  resource is fine.
- `priv/repo/migrations/*_alter_users_role_add_viewer.exs` — generated
  for the role-enum extension.
- `config/runtime.exs` — Oban Cron entry only if AshOban triggers don't
  cover what we want (they do — no config change expected).

### New (Tooling)

- `justfile` — add a `screenshots` recipe that drives Playwright against
  a running dev server to capture timeline screenshots into
  `docs/phase-1-screenshots/`.
- `docs/phase-1-screenshots/` — committed PNGs (acceptance criterion §2
  evidence). Subject to repo size; PNGs of the timeline view should
  be ≤ 200KB each.

### New (Specs)

- `specs/decisions/ADR-019-soft-delete-axis-records.md` — soft-delete
  pattern as a project convention.
- `specs/decisions/ADR-020-append-only-consent-ledger.md` — ledger
  pattern as a project convention.

## 3. Ash resources

### 3.1 `AshyWalnutDesk.Identity.Identity`

The customer/client record.

| Attribute | Type | Sensitive? | Allow nil? | Notes |
|---|---|---|---|---|
| `id` | `uuid_primary_key` | — | no | |
| `display_name` | `:ci_string` | yes | no | Domain-agnostic — deployer chooses what this means (full name, alias). |
| `primary_identifier_hash` | `:string` | yes | no | SHA-256(salt + normalized identifier). Raw identifier is **never** stored, per project invariant §8.1. |
| `notes_summary` | `:string` | yes | yes | Short operator-facing summary; defaults to nil. |
| `created_by_id` | `:uuid` | — | no | FK → `users.id`. Set server-side. |
| `deleted_at` | `:utc_datetime_usec` | — | yes | Soft-delete marker. Default reads filter `is_nil(deleted_at)`. |
| `created_at` / `updated_at` | `:utc_datetime_usec` | — | no | Standard timestamps. |

Relationships:

- `has_many :events, AshyWalnutDesk.Identity.Event`
- `has_many :appointments, AshyWalnutDesk.Identity.Appointment`
- `has_many :follow_ups, AshyWalnutDesk.Identity.FollowUp`
- `has_many :notes, AshyWalnutDesk.Identity.Note`
- `has_many :consents, AshyWalnutDesk.Identity.Consent`
- `belongs_to :created_by, AshyWalnutDesk.Accounts.User`

Actions (intent-revealing verbs, per AGENTS.md §6):

| Action | Type | Notes |
|---|---|---|
| `read` | read | Default-filters `is_nil(deleted_at)`. |
| `read_with_archived` | read | Admin-only; no filter. |
| `register_identity` | create | Accepts `display_name` + a raw primary identifier argument (sensitive, write-only); `HashPrimaryIdentifier` change hashes it. |
| `update_profile` | update | Accepts `display_name`, `notes_summary`. |
| `archive` | update | `SoftDelete` change; sets `deleted_at`. Idempotent (no-op if already archived). |
| `recover` | update | Admin-only; sets `deleted_at` back to nil. |

Policies:

- Bypass: `AshAuthenticationInteraction` (for system flows).
- `read`: `:admin` always; `:operator` always; `:viewer` always.
- `read_with_archived`: `:admin` only.
- `register_identity`: `:admin` or `:operator`.
- `update_profile`: `:admin` or `:operator`.
- `archive`: `:admin` or `:operator`.
- `recover`: `:admin` only.

Extensions: `AshPaperTrail.Resource` with `sensitive_attributes(:redact)`
and the same admin-only `Version` policy pattern as `User.Version`.

### 3.2 `AshyWalnutDesk.Identity.Event`

What happened — a service rendered to an Identity.

| Attribute | Type | Sensitive? | Allow nil? | Notes |
|---|---|---|---|---|
| `id` | `uuid_primary_key` | — | no | |
| `occurred_at` | `:utc_datetime_usec` | — | no | When the service was rendered. |
| `summary` | `:string` | yes | no | Operator-facing one-liner. |
| `body` | `:string` | yes | yes | Optional longer description. |
| `identity_id` | `:uuid` | — | no | FK → `identities.id`, `on_delete: :restrict`. |
| `recorded_by_id` | `:uuid` | — | no | FK → `users.id`. |
| `deleted_at` | `:utc_datetime_usec` | — | yes | Soft-delete marker. |
| timestamps | | | | |

Actions: `read` (filtered), `record_event` (create), `update_event`,
`archive`, `recover`.

Policies: same role pattern as Identity. Recovery admin-only.

Extension: `AshPaperTrail.Resource` with `:redact`.

### 3.3 `AshyWalnutDesk.Identity.Appointment`

Scheduled future encounter.

| Attribute | Type | Sensitive? | Allow nil? | Notes |
|---|---|---|---|---|
| `id` | `uuid_primary_key` | — | no | |
| `scheduled_for` | `:utc_datetime_usec` | — | no | When the appointment is. |
| `status` | `:atom` | — | no | One of `:scheduled`, `:cancelled`, `:completed`. Default `:scheduled`. |
| `summary` | `:string` | yes | no | |
| `identity_id` | `:uuid` | — | no | FK with `on_delete: :restrict`. |
| `recorded_by_id` | `:uuid` | — | no | |
| `deleted_at` | `:utc_datetime_usec` | — | yes | |
| timestamps | | | | |

Actions: `read`, `schedule_appointment` (create), `reschedule` (update —
permits `scheduled_for`), `cancel` (update — sets `status: :cancelled`),
`complete` (update — sets `status: :completed`; could be triggered when a
matching Event is recorded, but auto-linking is deferred), `archive`,
`recover`.

**No reminder/notification trigger.** Per requirements §3 out-of-scope,
appointments are record-only in Phase 1.

Policies: same role pattern; complete/cancel allowed for `:operator`+;
recovery admin-only.

Extension: `AshPaperTrail.Resource` with `:redact`.

### 3.4 `AshyWalnutDesk.Identity.FollowUp`

Scheduled post-encounter check-in. Mirrors Appointment but references an
originating Event.

Attributes (same shape as Appointment plus): `event_id` `:uuid`,
`on_delete: :restrict`, `allow_nil?: true` (a follow-up may exist
without a specific originating event).

Actions: same pattern as Appointment. `schedule_follow_up`,
`reschedule`, `cancel`, `complete`, `archive`, `recover`.

### 3.5 `AshyWalnutDesk.Identity.Note`

Free-text operator observation.

| Attribute | Type | Sensitive? | Allow nil? |
|---|---|---|---|
| `id` | `uuid_primary_key` | — | no |
| `body` | `:string` | yes | no |
| `identity_id` | `:uuid` | — | no |
| `recorded_by_id` | `:uuid` | — | no |
| `deleted_at` | `:utc_datetime_usec` | — | yes |
| timestamps | | | |

Actions: `read`, `record_note` (create), `edit_note` (update — body
only; `recorded_by_id` immutable), `archive`, `recover`.

Policies: same role pattern. Edit/archive allowed only to `:admin` or
to the note's `recorded_by_id` actor (self-edit).

Extension: `AshPaperTrail.Resource` with `:redact`.

### 3.6 `AshyWalnutDesk.Identity.Consent`

Append-only ledger of consent decisions. **No `deleted_at`, no update
action, no archive action.** Each row is immutable. See ADR-020.

| Attribute | Type | Sensitive? | Allow nil? | Notes |
|---|---|---|---|---|
| `id` | `uuid_primary_key` | — | no | |
| `consent_type` | `:atom` | — | no | E.g. `:contact`, `:data_processing`. Framework keeps it open; deployer's deployment repo lists allowed types. |
| `decision` | `:atom` | — | no | `:granted` or `:revoked`. |
| `effective_at` | `:utc_datetime_usec` | — | no | When the decision takes effect. Often = `created_at` but can be backdated. |
| `notes` | `:string` | yes | yes | Optional operator note. |
| `identity_id` | `:uuid` | — | no | FK with `on_delete: :restrict`. |
| `recorded_by_id` | `:uuid` | — | no | |
| `created_at` | `:utc_datetime_usec` | — | no | Immutable. **No `updated_at`** — rows never change. |

Actions: `read`, `record_consent` (create only). No update, no delete,
no archive.

A query function `current_consent/2` on the domain returns the most
recent row by `effective_at` for a given `(identity_id, consent_type)`.

Policies: `read` admits `:admin`, `:operator`, `:viewer`.
`record_consent` admits `:admin`, `:operator`. Viewers can see consent
history but cannot record new decisions.

Extension: **No `AshPaperTrail.Resource`.** Append-only IS the audit
trail; PaperTrail on an immutable resource adds noise without value.

## 4. LiveView components

### `IdentityLive.Index`

Route: `live "/identities", IdentityLive.Index`

Mount data: pagination params, role-based admin toggle for archived.
Events: pagination, search-by-name (uses `pg_trgm`).
Components: standard table.

### `IdentityLive.Show`

Route: `live "/identities/:id", IdentityLive.Show`

Mount data: the Identity (with related preloaded counts), the timeline
LiveComponent.

Events:
- `record_event`, `schedule_appointment`, `schedule_follow_up`,
  `record_note`, `record_consent` — handled by inline forms.
- `archive_identity`, `recover_identity` — admin/operator and admin
  respectively.

Components: `Timeline` (below).

### `IdentityLive.Timeline` (LiveComponent)

The merged chronological view. Reads from all five chronological
resources (Event, Appointment, FollowUp, Note, Consent), unions them
ordered by their respective time fields (`occurred_at`,
`scheduled_for`, `effective_at`, `created_at`).

Implementation note: the union is a single Ash query that uses a CTE
on Postgres; the Architect lists this as a candidate for the PM to
break into a story with a property test for ordering.

### `IdentityLive.New` / `IdentityLive.Edit`

Standard create/edit forms via `AshPhoenix.Form.for_action`.

## 5. External integrations

**None** in Phase 1. No new API calls, no new channels, no AI. The
nightly Token expunge runs via AshOban inside the existing Oban runtime.

## 6. Data flow

### 6.1 Identity creation

```text
IdentityLive.New (form)
   │
   ▼
AshPhoenix.Form.submit
   │
   ▼
Identity.register_identity
   │
   ▼ before_action
HashPrimaryIdentifier (SHA-256 + salt)
   │
   ▼
Repo.insert (identity row)
   │
   ▼
AshPaperTrail writes Version row (sensitive fields → "REDACTED")
   │
   ▼
LiveView redirects to IdentityLive.Show
```

### 6.2 Identity archive (soft-delete)

```text
operator/admin clicks "archive"
   │
   ▼
Identity.archive (update action)
   │
   ▼ change SoftDelete
sets deleted_at = utc_now if currently nil; else no-op
   │
   ▼
Repo.update + Version row
   │
   ▼
LiveView refreshes; archived rows hidden from default reads
```

### 6.3 Consent record (append)

```text
operator clicks "record consent: granted/revoked"
   │
   ▼
Consent.record_consent (create only)
   │
   ▼
Repo.insert (new row, never an update)
   │
   ▼
current_consent/2 query reflects new state immediately
   │
   ▼
Timeline shows the new row in chronological order
```

### 6.4 Token expunge (Phase 1 — TO-3)

```text
AshOban scheduler: 0 3 * * * UTC (daily 03:00)
   │
   ▼
Trigger `:expunge_tokens` on AshyWalnutDesk.Accounts.Token
   │
   ▼
Ash.bulk_destroy(Token, :expunge_expired, %{}, authorize?: false)
   │
   ▼
Removes rows where expires_at < now()
   │
   ▼
Telemetry event for ops visibility
```

## 7. Migration plan

1. Hand-authored migration: extend the `:role` enum on `users` to add
   `:viewer` (Postgres `ALTER TYPE … ADD VALUE`).
2. `mix ash_postgres.generate_migrations` produces six new tables
   (`identities`, `events`, `appointments`, `follow_ups`, `notes`,
   `consents`).
3. Each table FK to `identities` uses `ON DELETE RESTRICT` so a hard
   `DELETE` from outside Ash actions also fails — defense-in-depth for
   the soft-delete invariant.
4. Index on `(identity_id, deleted_at)` for each of the five
   soft-delete tables; covers the dominant timeline query.
5. Index on `(identity_id, consent_type, effective_at DESC)` for the
   `current_consent/2` query (Consent table).
6. AshPaperTrail generates `*_versions` tables and FKs as it did for
   `User` in Phase 0.

Rollback strategy: each generated migration carries its `down/0`. No
data migration in Phase 1, so rollback is `mix ecto.rollback` away;
seeded development data is recreated via the standard seed task.

## 8. Failure modes

| Failure | Degradation |
|---|---|
| Two operators archive the same Identity at the same instant | `SoftDelete` change is idempotent (no-op if `deleted_at` already set); second action returns the already-archived record. |
| Two operators record consent for the same (identity, type) within microseconds | Both rows persist (append-only ledger). `current_consent/2` returns whichever has the later `effective_at`; ties broken by `id` ordering. |
| Hard `DELETE FROM identities` from a DBA's psql session | FK `ON DELETE RESTRICT` rejects the delete; DBA must explicitly null out dependents first, surfacing the intent. |
| Postgres down during nightly token expunge | Oban retries the trigger; next-day run picks up the same expired rows. No data loss because the trigger reads what's currently in the table. |
| Timeline query slow for an identity with 10k events | Pagination cap (default 100 per axis per page); a property test enforces ordering correctness; performance test can be added in a later phase. |
| Operator with `:viewer` tries to record a note | Ash policy returns `Ash.Error.Forbidden`; UI hides the button via a `current_user.role` check. |
| `:viewer` role rolled out without UI updates | Policies are the gate; UI shows attempted-write actions as disabled. Tests cover both the policy denial and the UI affordance. |

## 9. Security considerations

- **Primary identifier never stored raw.** Same pattern as Phase 0
  `User.email_hash`: deterministic SHA-256 with a runtime-loaded salt
  (the existing `IDENTIFIER_HASH_SALT`).
- **All sensitive attributes** (`display_name`, `notes_summary`, `summary`,
  `body`, `notes`, etc.) marked `sensitive? true`. `AshPaperTrail` is
  configured with `sensitive_attributes(:redact)` on every Identity-axis
  resource that uses PaperTrail.
- **Version resources** (auto-generated by AshPaperTrail) get the same
  admin-only read mixin pattern Phase 0 established for `User.Version`.
- **Cross-resource ownership**: FK `ON DELETE RESTRICT` is enforced at
  the DB level. Ash policies enforce that all writes carry a valid
  `identity_id` and (where applicable) `recorded_by_id`.
- **Soft-delete recoverability** is an admin-only path; an operator
  cannot accidentally restore a record their teammate archived.
- **Append-only Consent** preserves a legally-defensible audit trail
  without depending on `AshPaperTrail` (which itself could fail or be
  misconfigured).
- **`:viewer` role**: read-only across the Identity axis; cannot write
  consent. UI affordances mirror policy denials so a viewer never sees
  a button they can't use.

## 10. Safety review

Per AGENTS.md §7:

| Inviolable rule | Phase 1 application |
|---|---|
| §7.1 No domain assertions in AI output without validation | N/A — no AI in Phase 1. |
| §7.2 Human-in-the-loop for ALL sends | N/A — no sends in Phase 1. |
| §7.3 Audit trail mandatory | All five PaperTrail-enabled resources + the Consent ledger are audited. Tests assert version rows are produced for state changes. |
| §7.4 Sensitive data handling | All identifying/free-text fields marked `sensitive? true`. PaperTrail `:redact`. Raw primary identifier hashed before storage. |
| §7.5 Disclosure | N/A — no AI-assisted messages in Phase 1. |

Sensitive data flow boundaries:

- **At rest**: hashed primary identifier; redacted sensitive fields in
  PaperTrail version rows; admin-only access to archived rows.
- **In transit**: TLS at the edge per BASELINE §12 (deployer concern,
  tracked as TO-2).
- **In logs**: standard Phoenix logger respects `sensitive?` via
  `Ash.PlugHelpers`-style redaction. No raw PII in production logs.

## 11. Testing strategy

- **Unit (`mix test`)**
  - Per resource: action policy denial/allow for each of the three
    roles × each action.
  - `HashPrimaryIdentifier` change: deterministic given the same salt,
    normalized for whitespace/case.
  - `SoftDelete` change: idempotent (second invocation = no-op).
  - `Consent.current_consent/2` returns the latest by `effective_at`,
    ties broken by `id`.
  - `User.Version`-style admin-only read policy on each Identity-axis
    Version resource.
- **Integration (`Phoenix.LiveViewTest`)**
  - Full create-Identity → record-Event → schedule-Appointment →
    record-Note → record-Consent → view-Timeline flow under an
    `:operator` actor.
  - `:viewer` actor sees the timeline but UI hides write buttons; Ash
    actions reject any write attempts.
  - Archive flow: archived Identity disappears from default Index;
    `read_with_archived` (admin) shows it; admin `recover` restores.
- **Property-based (`StreamData`)**
  - Timeline ordering: for any set of mixed-type events with random
    timestamps, the merged timeline is monotonically non-decreasing
    by time.
  - Append-only invariant: a sequence of `record_consent` calls never
    decreases the `current_consent` row count.
- **Background (`AshOban`)**
  - The `:expunge_tokens` trigger destroys rows where
    `expires_at < now()` and leaves all other rows intact.
- **Manual / Playwright**
  - The `just screenshots` recipe drives the full flow and emits a
    deterministic set of PNGs into `docs/phase-1-screenshots/`. These
    are committed; CI does not regenerate them, but a future CI gate
    could diff the output if drift becomes a concern.

## 12. Open technical questions

1. **AshOban trigger surface**: do we put the `:expunge_tokens` trigger
   on the `Token` resource (cleanest, but couples Phase 1 work to a
   Phase 0 module) or in a separate `Accounts.OperationalTasks` shim?
   Recommendation: on the `Token` resource itself.
2. **Search on Index**: `pg_trgm` was installed in Phase 0 but never
   exercised. Index filter uses it for `display_name` similarity. Open
   question: minimum similarity threshold? Recommendation: defer the
   threshold to a story-level decision (default 0.3 from `pg_trgm`).
3. **Consent type controlled vocabulary**: framework leaves
   `consent_type` open; should `specs/phase-1/architecture.md` recommend
   a default set (e.g. `:contact_consent`, `:data_processing`) or stay
   silent and let deployers declare? Recommendation: stay silent
   (matches ADR-006). A deployer's compliance docs will enumerate.
4. **`recorded_by_id` immutability**: if a User is archived in a future
   phase, do existing notes/events/etc. owned by them get a stale FK?
   Recommendation: leave it; the FK is to the immutable historic
   `users.id` value; archiving a User doesn't delete the row, so the FK
   remains valid. Document in the eventual User-archiving story.
5. **Pagination contract**: Index page size = 100? Timeline page size
   per axis = 100? Recommendation: 100 across the board; revisit in
   Phase 2 if real data shows otherwise.

---

*Architecture drafted by BMAD Architect persona. When approved, activate
the PM persona to break Phase 1 into stories.*
