# Phase 1 — Requirements

## 1. Goal

Deliver the Identity axis foundation (Who/When) so operators can create, read, update, and audit customer identity records, encounters, appointments (including follow-ups via an `appointment_type` enum), and operator notes under strict authorization and sensitive-data controls.

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 1 stories merge.
- [ ] Identity-axis resources exist for customer identity, event/encounter, appointment, and note, and they are reachable only through named Ash actions (no direct data-layer access path).
- [ ] Every Identity-axis resource has explicit authorization policies; unauthenticated callers are denied by default for non-public actions.
- [ ] Sensitive customer fields are marked and handled as sensitive, and raw sensitive values are not persisted in audit payloads in plaintext.
- [ ] The project-level invariant "raw primary identifiers are never stored when hashing is required" is enforced for the Identity resource.
- [ ] **Appointment is one resource, not two.** Follow-ups are modeled via an `appointment_type` enum (`:initial | :follow_up | :recurring`) plus a nullable `originating_event_id` FK that is required when type is `:follow_up`.
- [ ] Identity timeline behavior is observable: operators can view a customer's linked events, appointments (including follow-ups), and notes in chronological order.
- [ ] Cross-resource ownership constraints are enforced: event/appointment/note records cannot exist without an owning identity context.
- [ ] Audit trail coverage is active for Identity-axis sensitive-record changes, with tests asserting that key state transitions produce version/audit entries.
- [ ] **Soft-delete only** on every Identity-axis resource: each resource has a `deleted_at` timestamp; reads filter deleted rows by default; admin can recover. No hard-delete action ships in Phase 1.
- [ ] A new `:viewer` role is added to the role enum alongside `:admin` and `:operator`. Identity-axis read policies admit `:viewer`; write policies do not.
- [ ] Appointment records carry a `scheduled_for` timestamp and are observable to operators, but Phase 1 does **not** ship a sending/reminder pipeline (record-only — deferred to Phase 4).
- [ ] Identity-timeline UX evidence: an automated `Phoenix.LiveViewTest` E2E flow exercises create → link → view-timeline, **plus** committed Playwright-driven screenshots of the timeline UI showing create + linked records (one screenshot per major UX state). The screenshots live under a tracked path (e.g. `docs/phase-1-screenshots/`) and the script that produces them is reproducible from `just`.
- [ ] TO-3 from `specs/security/known-trade-offs.md` is resolved in this phase: expired authentication tokens are expunged on a recurring schedule and verified by tests.

## 3. Scope

### In scope
- Identity-axis domain capability requirements for:
  - Customer identity records (Who)
  - Events/encounters and appointments — record-only, no reminder/send pipeline. Follow-ups are appointments with `appointment_type: :follow_up` + an originating-event link.
  - Operator notes linked to identity context
- Phase-level authorization, sensitive-data handling, and audit requirements for all Identity resources.
- `:viewer` role added to the role enum; read-only access pattern for Identity resources.
- Soft-delete pattern (`deleted_at` + default-filtered reads + admin recovery) on every Identity resource.
- Identity-oriented operator UX requirements in LiveView sufficient to prove authenticated use of the new domain records, with Playwright screenshot evidence of the timeline UX.
- Resolution of TO-3 (expired token expunge) as Phase 1 security hygiene tied to active operator usage growth.

### Out of scope (deferred)
- **Consent resource.** `specs/architecture.md §2` lists Consent as an Identity-axis resource, but Phase 1 has no enforcement point that reads it (no send pipeline, no AI gate). A Consent resource with no consumer is bookkeeping nothing depends on. Deferred to the first phase that needs it — likely Phase 4 alongside the AI-draft / send pipeline. The candidate append-only ledger design is recorded in `specs/phase-1/architecture.md §3.5` for continuity.
- A separate `FollowUp` resource. Merged into `Appointment` via the `appointment_type` enum to remove a near-duplicate schema.
- Conversation/message/channel pipeline behavior (Phase 2).
- External channel adapters and webhook integrations (Phase 3).
- AI draft generation, validator semantics, and send countdown flows (Phase 4).
- Knowledge-axis resources and retrieval behavior (Phase 5).
- Reminder/notification sending for appointments — deferred to Phase 4 when the send pipeline ships.
- Hard-delete of Identity records — deferred to a later governance phase if ever; the audit chain (ADR-016) and inviolable rule §7.4 make hard-delete a deliberate decision, not a default.
- Operator role partitioning beyond `:admin`/`:operator`/`:viewer` — deferred to first deployer onboarding (per ADR-006: domain as configuration).
- Per-record operator assignment (`assigned_operator_id` etc.) — deferred; revisit when a deployer needs work allocation.
- Deployment-specific legal/compliance wording, retention windows, and jurisdictional policy documents (deployer repo per ADR-010).
- Full cross-axis overview dashboard behavior (later phase when multiple axes are populated).

## 4. Story breakdown

| # | Story | Est | Depends on | Status |
|---|---|---|---|---|
| 1.1 | Identity domain bootstrap + viewer role | 2h | — | ready |
| 1.2 | Identity resource + hashing + soft-delete base pattern | 3h | 1.1 | ready |
| 1.3 | Event resource linked to Identity | 2h | 1.2 | ready |
| 1.4 | Appointment resource with follow-up validation | 3h | 1.2, 1.3 | ready |
| 1.5 | Note resource with ownership-aware editing | 2h | 1.2 | ready |
| 1.6 | Identity LiveViews + timeline UI | 3h | 1.2, 1.3, 1.4, 1.5 | ready |
| 1.7 | Property-based invariants for timeline and soft-delete | 2h | 1.2, 1.3, 1.4, 1.5, 1.6 | ready |
| 1.8 | TO-3 token expunge schedule via AshOban | 1h | 1.1 | ready |
| 1.9 | Playwright screenshot evidence for Identity timeline UX | 2h | 1.6 | ready |
| 1.10 | Phase 1 Identity-axis integration test gate | 2h | 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9 | ready |

## 5. Dependencies

### External
- None required beyond existing Phase 0 baseline tooling/runtime.
- Deployment-specific compliance definitions remain an external input and are not blocked for framework-level Phase 1 completion.

### Internal
- Phase 0 completed and green on `main` (auth, policies, audit, CI, and gettext foundations).
- Accounts subsystem available for authenticated operator context.
- Security trade-off register available at `specs/security/known-trade-offs.md` (TO-1/TO-2 tracked, TO-3 to be resolved here).

## 6. Risks

| Risk | Mitigation |
|---|---|
| Identity requirements drift into Interaction scope | Keep phase acceptance tied to Who/When only; defer channel/message semantics explicitly to Phase 2. |
| Sensitive-data leakage in audit/version payloads | Add explicit acceptance checks and regression tests for redaction/sensitive handling on Identity resources. |
| Consent shape designed without a real consumer drifts in Phase 4 | Defer Consent out of Phase 1 entirely; revisit when the AI-draft / send pipeline first reads consent (candidate design recorded in architecture §3.5). |
| Authorization gaps as resources proliferate | Require explicit policy coverage per resource/action and include unauthenticated/unauthorized negative tests in phase verification. |
| TO-3 remains deferred and accumulates stale auth token rows | Treat TO-3 as in-scope phase hygiene and require a recurring expunge proof in tests before phase completion. |
| Timeline usability degrades with fragmented records | Require observable linked chronological view behavior as an acceptance criterion, not an optional UX refinement. |

## 7. Open questions (resolved)

- [x] **Soft-delete/archive in Phase 1?** — Yes, soft-delete only (`deleted_at` + default-filtered reads + admin recovery). Hard-delete is forbidden in Phase 1; revisit only if a future governance phase explicitly authorizes it.
- [x] **Consent versioning model?** — Revisited during Architect pass: Consent has no Phase 1 reader (no send pipeline, no AI gate). Deferred to its first consumer phase (likely Phase 4). The candidate append-only ledger design is recorded in `specs/phase-1/architecture.md §3.5` for continuity; the actual ADR is written by the Architect of that future phase with a real consumer in mind.
- [x] **Additional operator roles?** — Add `:viewer` (read-only) alongside `:admin`/`:operator`. Further partitioning (per-record assignment, additional roles) deferred until a real deployer onboards (per ADR-006).
- [x] **Reminders/notifications for appointments?** — Record-only in Phase 1 (covers both initial and follow-up appointments via `appointment_type`). Sending pipeline lands in Phase 4 (AI Drafts + send) where the send infrastructure exists.
- [x] **Identity-timeline UX evidence?** — `Phoenix.LiveViewTest` E2E flow **plus** committed Playwright screenshots of the timeline UI under a tracked path. Screenshots are reproducible via `just`.

Each answer is settled here. Q2 was re-opened during the Architect
pass and Consent was deferred (see `specs/phase-1/architecture.md
§3.5` for the rationale); the rest stand as originally resolved.

---
*Requirements drafted by BMAD Analyst persona (Codex). Architect pass
complete (`specs/phase-1/architecture.md`, ADR-019). Next: PM persona
breaks Phase 1 into stories.*
