# Phase 2 — Requirements

## 1. Goal

Deliver the Interaction-axis schema and the **four-stage record chain** (ADR-016) — Inbox → Draft → Action → Compensation — with hash-chained AuditEvents and a working operator UI for manual draft composition, 5-second-countdown approval, and end-to-end execution against a placeholder channel adapter. Real channel integration and AI draft generation remain deferred to Phases 3 and 4.

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 2 stories merge.
- [ ] Interaction-axis resources exist for `Conversation`, `Message`, `Channel`, `Inbox`, `Draft`, `Action`, `Compensation`, and `AuditEvent`, reachable only through named Ash actions (no direct data-layer access path).
- [ ] Every Interaction-axis resource has explicit authorization policies; unauthenticated callers are denied by default for non-public actions.
- [ ] Every `Conversation` is linked to exactly one `Channel` and exactly one `Identity` (data invariant §8.3 of `specs/architecture.md`).
- [ ] Every `Message` is linked to exactly one `Conversation` (data invariant §8.2).
- [ ] Every outbound `Message` carries a non-null `approved_by_id` referencing the User who approved (invariant §8.4); writes that bypass this are rejected at the action layer.
- [ ] **Four-stage chain is mandatory.** Every operator-initiated send produces, in order, an `Inbox` row, a `Draft`, an `Action`, *and* a `Compensation` row — with the Compensation created at Action-approval time, never lazily. Verified by tests.
- [ ] **5-second countdown is enforced** between draft approval and Action execution (invariant §8.5, ADR-013). The countdown is a server-side delay, not just a UI animation; bypass via direct Ash action call is rejected.
- [ ] **AuditEvent hash chain is intact and verifiable.** Every chain transition (`Inbox → Draft`, `Draft → Action`, `Action → Compensation`, status changes) writes an immutable `AuditEvent` whose `prev_hash` references the previous event's hash. A `mix audit.verify` task (or equivalent) walks the chain and exits non-zero on tampering.
- [ ] **Compensation is registered, not invoked, in Phase 2.** Every Action that executes also creates a `Compensation` row with `status: :registered` and the remediation text/template captured at approval time. Operator UI to *trigger* the compensation send ships with the first real channel adapter (Phase 3).
- [ ] **Placeholder channel adapter ships.** A `Channel.Adapter.Stub` implements the `Channel.Adapter` behaviour with a no-op outbound (records `Action.status: :executed` without an external API call) so the chain is testable end-to-end. Real adapters (SMS, email, etc.) land in Phase 3.
- [ ] **"Honest framing" is enforced in code** (ADR-016): any UI surface or status string that could read as "unsend" is rejected by a test that greps Phoenix templates + gettext strings.
- [ ] Inbox source in Phase 2 is **operator-initiated only**. An operator can create an Inbox row referencing an existing Identity from Phase 1; scheduled / inbound webhook sources are deferred to Phase 3.
- [ ] Drafts are **operator-composed (manual) in Phase 2**. AI-generated drafts, prompt builders, and validator integration are deferred to Phase 4 per BASELINE §7. The `Draft` resource has the schema to hold AI metadata (prompt, model, response, validator output per invariant §8.6); those columns are nullable in Phase 2 and required in Phase 4.
- [ ] **Soft-delete pattern** (per ADR-019) is applied to every Interaction-axis resource that carries operator-visible state (`Conversation`, `Message`, `Inbox`, `Draft`). `Action`, `Compensation`, and `AuditEvent` are **immutable** and never soft-deleted (audit-trail integrity).
- [ ] Audit trail coverage (AshPaperTrail) is active for sensitive-record changes on Interaction-axis resources, with tests asserting that approval, execution, and status transitions produce version entries.
- [x] Operator UX evidence: a `Phoenix.LiveViewTest` E2E flow exercises *create Inbox → compose Draft → approve with countdown → see Action + Compensation*, plus committed Playwright screenshots of the chain visualization UI (one screenshot per major UX state — open Inbox, drafting, countdown, executed). Screenshots live under `docs/phase-2-screenshots/` and are reproducible from `just`.

## 3. Scope

### In scope
- Interaction-axis domain capability requirements for:
  - `Conversation` (a thread, linked to one Channel + one Identity)
  - `Message` (single exchange within a Conversation)
  - `Channel` (the medium; Phase 2 ships only the placeholder/stub adapter)
  - `Inbox` (incoming intent; operator-initiated in Phase 2)
  - `Draft` (proposed reply; operator-composed in Phase 2)
  - `Action` (the actual send; routes to the stub adapter in Phase 2)
  - `Compensation` (remediation registered at approval time)
  - `AuditEvent` (hash-chained event record, immutable)
- The `Channel.Adapter` behaviour and its stub implementation.
- Server-side enforcement of the 5-second countdown (ADR-013) between draft approval and Action execution.
- Operator LiveView surface sufficient to drive the four-stage chain end-to-end: Inbox list, Conversation view, Draft composer, countdown approval UI, chain visualization (per ADR-016 follow-up).
- `mix audit.verify` (or equivalent) hash-chain verification utility.
- Phase-level authorization, sensitive-data handling, and audit requirements for all Interaction resources.
- Property-based tests asserting four-stage-chain invariants (every Action has a Compensation; every Compensation has an Action; chain hash continuity holds under concurrent writes).
- Identity-axis ↔ Interaction-axis cross-linking acceptance: Conversation creation requires a valid Identity FK and is denied if the Identity is soft-deleted.

### Out of scope (deferred)
- **Real channel adapters.** Phase 3 ships the first one (SMS or messaging — deployer-influenced choice per ADR-010). Inbound webhook plumbing also lands in Phase 3.
- **AI draft generation.** Phase 4 wires AnthropicClient + PromptBuilder + Safety.Validator (per ADR-004 + AGENTS.md §7.1). Phase 2 Draft schema has nullable AI columns ready to be filled in Phase 4.
- **Compensation invocation UI.** Phase 2 *registers* Compensation rows at approval time but does not ship operator UI to *send* the compensation. Compensation invocation lands in Phase 3 alongside the first real channel adapter (because there's nothing meaningful to compensate without an external send).
- **`Template` resource (pre-approved auto-responses).** Templates only meaningfully exist with a real channel context; deferred to Phase 3.
- **Inbound message ingestion.** No webhook receiver, no signature verification, no inbound → Inbox mapping in Phase 2 (Phase 3).
- **Scheduled / cron-driven Inbox creation** (e.g. "create an Inbox row 3 days after each completed Appointment for follow-up"). Deferred to Phase 3 or later — keeps Phase 2 focused on the chain mechanics.
- **Overview-layer aggregator UI across axes** (deferred to a later cross-axis phase).
- **Hard-delete of Interaction-axis state** — never; the audit chain (ADR-016) plus inviolable rule §7.3 make hard-delete a separate governance decision.
- **Consent resource.** Still no consumer in Phase 2 — drafts are operator-composed, no AI gate, no external send. Deferred (continues the Phase 1 deferral; candidate design remains in `specs/phase-1/architecture.md §3.5`). Phase 4 is the likely consumer.
- **Multi-tenant / cross-deployment concerns** (Phase 5+).
- **Deployment-specific compliance, channel credentials, rate-limit policy.** Per ADR-010 these belong in the deployer's private repo.

## 4. Story breakdown

| # | Story | Est | Depends on | Status |
|---|---|---|---|---|
| 2.1 | Security entry gate (ADR-020 cookie on_mount + `:jti` restore + ADR-021 prod TLS/cookie hardening + runtime-resolved session plug) | 4h | — | ready |
| 2.2 | Interaction domain bootstrap + resource skeletons | 2h | 2.1 | ready |
| 2.3 | Mutable Interaction resources + soft-delete policies | 3h | 2.2 | ready |
| 2.4 | Immutable chain resources + adapter contract + adapter allowlist | 2h | 2.2 | ready |
| 2.5 | Chain transition actions + server countdown + concurrent-approve race guard | 3h | 2.3, 2.4 | ready |
| 2.6 | Hash-chained AuditEvent writer + closed payload contract + `mix audit.verify` | 4h | 2.4, 2.5 | ready |
| 2.7 | Operator LiveView flow for Inbox-to-Action chain | 3h | 2.5, 2.6 | ready |
| 2.8 | Safety framing guard + audit coverage assertions | 2h | 2.7 | ready |
| 2.9 | Reproducible UX screenshots + phase docs sync | 2h | 2.7, 2.8 | ready |
| 2.10 | Phase 2 integration gate (full AC verification) | 3h | 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9 | ready |

**Phase total: 28h** (up from initial 26h after R1/R2 review estimate calibration on 2.1 and 2.6).

## 5. Dependencies

### External
- None new beyond Phase 0/1 baseline. The first real channel adapter (Phase 3) will introduce an external dependency; Phase 2 deliberately avoids that to keep scope bounded.
- Deployment-specific compliance and channel credentials remain external and are not blocked for framework-level Phase 2 completion.

### Internal
- Phase 0 (foundation: auth, policies, audit, gettext, CI) and Phase 1 (Identity axis: `Identity`, `Event`, `Appointment`, `Note`) shipped on `main`.
- `AshPaperTrail` mixin pattern from Phase 1 (`AshyWalnutDesk.AdminOnlyVersions`) reused on Interaction-axis resources where appropriate.
- Security trade-off register (`specs/security/known-trade-offs.md`):
  - **TO-1 resolved by ADR-020** — Story 2.1 implements the custom cookie-loading `on_mount` and flips `Accounts.User.session_identifier` back to `:jti`, restoring per-session JWT revocation before any send-related story merges.
  - **TO-2 resolved by ADR-021** — Story 2.1 also lands the `PHX_HOST != "localhost"` prod block in `config/runtime.exs` (`force_ssl: [hsts: true]` + `secure: true` session cookie).
  - TO-4, TO-5, TO-6 — unchanged; tracked.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Four-stage chain rules ("always create Compensation," "honest framing") get watered down in implementation | Encode each rule as a phase acceptance criterion above; add property/integration tests that fail the build if a chain transition skips the Compensation row or a UI string reads as "unsend." |
| 5-second countdown becomes a UI-only animation (bypassable via direct Ash action) | Enforce the countdown server-side (e.g. a `change before_action` that rejects Action execution if `approved_at` is < 5s old). Test by calling the action programmatically with `approved_at` in the recent past and asserting rejection. |
| Audit-chain hash continuity breaks under concurrent writes | Property-test concurrent Action approvals and assert chain integrity; serialize hash writes via DB constraint or `SELECT FOR UPDATE` on the prev event. |
| TO-1 (`:unsafe` session) carries into Phase 2 and a leaked JWT now grants send privileges | Treat TO-1 resolution as a phase entry blocker; document the decision (re-enable `:jti`, or short-lived tokens + re-auth on send) before Story 2.1 starts. |
| `Channel.Adapter` behaviour drafted speculatively, then Phase 3's first real adapter forces incompatible changes | Keep the stub adapter minimal: just enough to record `Action.status: :executed`. Resist temptation to design for SMS/email/etc. now; Phase 3 will refine the behaviour. |
| Operator UI for the four-stage chain becomes a screen-per-stage maze | Architect must converge on a single chain-visualization component (per ADR-016 follow-up). Acceptance criterion already requires it; resist branching layouts. |
| Phase 2 ships without observable evidence the chain works under stress | Property tests (StreamData) on chain invariants + Playwright screenshots of each chain stage as committed evidence (Phase 1 pattern). |
| Identity-axis ↔ Interaction-axis cross-link rules forgotten (e.g. soft-deleted Identity should not accept new Conversations) | Acceptance criterion + regression test on Conversation create with a soft-deleted Identity FK. |

## 7. Open questions (resolved — push back in PR review if you disagree)

- [x] **Does Phase 2 ship a stub channel adapter so the chain executes end-to-end, or stop at `Action.status: :pending` pending Phase 3?** — Ship the stub. Without it, the 5-sec countdown, the AuditEvent chain, and the Compensation-on-approval rule are all untestable in isolation. The stub is a no-op (no external call) but completes `Action.status: :executed` so every chain transition fires.

- [x] **Is `Template` a Phase 2 resource?** — No. Templates are pre-approved auto-responses; they're only meaningful with a real channel context (compliance windows, template-approval processes are channel-specific). Defer to Phase 3.

- [x] **Compensation: invocation UI in Phase 2 or only registration?** — Registration only. Compensation rows are created at Action-approval time per ADR-016's "always create Compensation" discipline; the operator-facing UI to *invoke* compensation ships with the first real channel adapter (Phase 3), when there's an actual external send to compensate.

- [x] **Inbox source in Phase 2 — operator-initiated only, or scheduled too?** — Operator-initiated only. Phase 2 focuses on the chain mechanics; scheduled Inbox creation (e.g. follow-up reminders from Phase 1 Appointments) is a Phase 3+ concern when there's a real send path.

- [x] **Manual drafts in Phase 2 — confirm AI is deferred?** — Confirmed. Phase 4 wires AI per BASELINE §7. Phase 2 Draft schema carries nullable AI-metadata columns (prompt, model, response, validator output) so Phase 4 doesn't need a migration to fill them.

- [x] **Soft-delete pattern on Interaction resources?** — Apply to `Conversation`, `Message`, `Inbox`, `Draft` (operator-visible state). `Action`, `Compensation`, `AuditEvent` are **immutable** — never soft-deleted — because the audit chain depends on them being permanent.

- [x] **TO-1 (`session_identifier(:unsafe)`) — Phase 2 entry decision?** — Resolved by **ADR-020** (custom cookie-loading `on_mount` + flip `:unsafe` → `:jti`). Story 2.1 implements.

- [x] **TO-2 (session `secure` flag + `force_ssl`) — close in Phase 2 or stay deferred?** — Resolved by **ADR-021** (close in Phase 2: `PHX_HOST != "localhost"`-keyed prod block in `config/runtime.exs` for `force_ssl: [hsts: true]` and `secure: true` cookie). Story 2.1 implements.

---

*Phase 2 BMAD complete on `main`: Analyst (PR #20) → Architect + PM (PR #21). Architect-redraft pass against R1/R2 review by Claude+Codex applied here. Stories 2.1–2.10 ready for implementation; story 2.1 is the security entry gate (ADR-020 + ADR-021) and must merge before any send-related story.*
