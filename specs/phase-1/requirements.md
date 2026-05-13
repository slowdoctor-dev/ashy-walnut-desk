# Phase 1 — Requirements

## 1. Goal

Deliver the Identity axis foundation (Who/When) so operators can create, read, update, and audit customer identity records, encounters, scheduling records, follow-up records, notes, and consent records under strict authorization and sensitive-data controls.

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 1 stories merge.
- [ ] Identity-axis resources exist for customer identity, event/encounter, appointment, follow-up, note, and consent, and they are reachable only through named Ash actions (no direct data-layer access path).
- [ ] Every Identity-axis resource has explicit authorization policies; unauthenticated callers are denied by default for non-public actions.
- [ ] Sensitive customer fields are marked and handled as sensitive, and raw sensitive values are not persisted in audit payloads in plaintext.
- [ ] The project-level invariant "raw primary identifiers are never stored when hashing is required" is enforced for the Identity resource.
- [ ] Consent is modeled as a first-class record with auditable create/update lifecycle and effective-state visibility for operators.
- [ ] Identity timeline behavior is observable: operators can view a customer's linked events, appointments, follow-ups, notes, and consent history in chronological order.
- [ ] Cross-resource ownership constraints are enforced: event/appointment/follow-up/note/consent records cannot exist without an owning identity context.
- [ ] Audit trail coverage is active for Identity-axis sensitive-record changes, with tests asserting that key state transitions produce version/audit entries.
- [ ] LiveView coverage exists for at least one authenticated end-to-end Identity flow (create or update customer identity + related record + verification of visible result).
- [ ] TO-3 from `specs/security/known-trade-offs.md` is resolved in this phase: expired authentication tokens are expunged on a recurring schedule and verified by tests.

## 3. Scope

### In scope
- Identity-axis domain capability requirements for:
  - Customer identity records (Who)
  - Events/encounters, appointments, and follow-ups (When)
  - Operator notes and consent records linked to identity context
- Phase-level authorization, sensitive-data handling, and audit requirements for all Identity resources.
- Identity-oriented operator UX requirements in LiveView sufficient to prove authenticated use of the new domain records.
- Resolution of TO-3 (expired token expunge) as Phase 1 security hygiene tied to active operator usage growth.

### Out of scope (deferred)
- Conversation/message/channel pipeline behavior (Phase 2).
- External channel adapters and webhook integrations (Phase 3).
- AI draft generation, validator semantics, and send countdown flows (Phase 4).
- Knowledge-axis resources and retrieval behavior (Phase 5).
- Deployment-specific legal/compliance wording, retention windows, and jurisdictional policy documents (deployer repo per ADR-010).
- Full cross-axis overview dashboard behavior (later phase when multiple axes are populated).

## 4. Story breakdown (filled later by PM)

| # | Story | Estimate | Depends on | Status |
|---|---|---|---|---|

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
| Ambiguous consent semantics across deployers | Keep consent requirements framework-level (recorded state transitions + visibility), and defer legal wording/content policy to deployer compliance specs. |
| Authorization gaps as resources proliferate | Require explicit policy coverage per resource/action and include unauthenticated/unauthorized negative tests in phase verification. |
| TO-3 remains deferred and accumulates stale auth token rows | Treat TO-3 as in-scope phase hygiene and require a recurring expunge proof in tests before phase completion. |
| Timeline usability degrades with fragmented records | Require observable linked chronological view behavior as an acceptance criterion, not an optional UX refinement. |

## 7. Open questions

- [ ] Should Identity record lifecycle include soft-delete/archive requirements in Phase 1, or is hard-delete prohibition deferred to a later governance phase?
- [ ] Is consent versioning required as immutable append-only history in Phase 1, or is update-in-place with audit trail acceptable for now?
- [ ] What minimum operator roles beyond `admin`/`operator` are required for Identity access partitioning in Phase 1 (if any)?
- [ ] Should appointment/follow-up scheduling in Phase 1 include reminder/notification behavior, or remain record-only until Phase 2/3 integrations?
- [ ] What Phase 1 completion evidence is required for identity timeline UX: automated test-only proof, or test + manual acceptance checklist?

---
*Requirements drafted by BMAD Analyst persona. When approved, activate the Architect persona for technical design.*
