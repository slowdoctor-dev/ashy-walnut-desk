# Phase 3 — Requirements

## 1. Goal

Deliver Twilio SMS as the first production-grade (non-stub) channel adapter end-to-end: inbound webhook ingestion plus outbound send execution with provider-aware reliability, while preserving Phase 2 safety invariants (human approval, 5-second countdown, immutable audit chain).

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 3 stories merge.
- [ ] Twilio SMS adapter is integrated end-to-end as the Phase 3 real provider.
- [ ] Outbound send path for Twilio runs through the existing Phase 2 chain (`Inbox -> Draft -> Action -> Compensation`) and does not bypass approval/countdown/audit invariants.
- [ ] `Action.adapter_response` stores provider response metadata; provider auth credentials never appear in `Action`, `Message`, or `AuditEvent` rows.
- [ ] `Interaction.Adapter` behaviour is the only provider extension point: a future provider lands as a single-file `Interaction.Adapters.<Provider>` module plus allowlist entry, without modifying Twilio adapter code, `Action.execute`, or Compensation actions.
- [ ] Adapter-contract conformance tests run against Twilio and a test-only `Interaction.Adapters.Echo` fixture; both must satisfy the same adapter contract.
- [ ] Inbound webhook endpoint exists for Twilio and creates/links `Inbox`, `Conversation`, and inbound `Message` via named Ash actions only.
- [ ] Inbound `Inbox` creation uses an internal-only action path (non-operator path) dedicated to webhook intake; operator-only `Inbox.:record_inbox` remains operator/admin-only.
- [ ] Webhook authenticity is enforced server-side (Twilio signature verification); invalid signatures are rejected and audited.
- [ ] Inbound conversation threading default is explicit and test-covered: thread to the most recent non-archived Conversation for the same `(identity_id, channel_id)` pair; if none exists, create a new Conversation.
- [ ] Inbound identity default is explicit and test-covered:
  - Existing identity: link inbound traffic to the existing Identity.
  - Unknown identifier: create a new Identity with deterministic placeholder display name and link inbound traffic.
  - Malformed/ambiguous identifier signal: hold in a deterministic, auditable intake-failure path for operator triage (no silent drop).
- [ ] Idempotency is enforced for inbound webhooks and outbound provider calls; replayed deliveries do not create duplicate business records.
- [ ] Outbound idempotency key is deterministic from `action_id` (or an equivalent one-to-one action key) and stable across retries.
- [ ] Provider/network failures follow explicit retry policy and terminal-failure policy, executed through background job infrastructure (Oban), with no autonomous bypass of human approval rules.
- [ ] Channel-level enable/disable state is honored at execution time; disabled channels cannot send.
- [ ] Public webhook endpoint(s) are protected by abuse controls (rate/traffic throttling); abusive callers receive deterministic non-success responses (e.g., 429), test-covered.
- [ ] Webhook URL/bootstrap configuration is documented and executable via a preflight validation gate that exits non-zero when required configuration is missing/invalid.
- [ ] Compensation invocation UI ships in this phase: operator can trigger compensation from the chain view through named action flow, using the same Twilio adapter path and preserving audit trail.
- [ ] Compensation invocation is subject to the same 5-second countdown rule as other outbound sends (no carve-out in this phase).
- [ ] Admin audit-chain viewer (`AuditLive.Chain`) ships in this phase, admin-only, with chain-topic filtering and hash-continuity visibility aligned with CLI verification semantics.
- [ ] Honest-framing and audit-chain checks from Phase 2 remain green; no regression in `mix audit.verify` behavior.
- [ ] Security hardening controls from Phase 2 remain intact: no `authorize?: false` leaks in LiveView read surfaces for chain data, and no operator-callable actions can forge chain stages.

## 3. Scope

### In scope

- Twilio SMS real-adapter integration.
- Provider-specific outbound execution from `Action.execute` through adapter boundary.
- Provider-specific inbound webhook ingestion and mapping to Interaction resources.
- Internal-only inbound Inbox action path for webhook intake.
- Inbound identifier matching/creation behavior for unknown senders, with deterministic auditable outcomes.
- Inbound threading default on `(identity_id, channel_id)` with explicit fallback to new Conversation.
- Idempotency, replay protection, retry, and terminal failure handling for reliable messaging operations.
- Public webhook abuse controls and configuration preflight validation.
- Compensation invocation operator flow (deferred from Phase 2), including countdown enforcement.
- Admin audit-chain viewer (`AuditLive.Chain`) for chain inspection.
- Operational controls on channels (enabled/disabled behavior at send time).
- Regression coverage for Phase 2 invariants under real-adapter execution.
- Adapter extensibility conformance tests (`Twilio` + test-only `Echo` fixture).

Safety implications in scope:
- Inbound payloads can contain sensitive identifiers/content and must be treated as sensitive data.
- Outbound sends are real external effects; countdown + explicit approval remain mandatory and test-enforced.
- Webhook trust boundary must be authenticated to prevent forged inbound records.
- Retry and replay handling must prevent duplicate sends and duplicate chain stages.

### Out of scope

- Multi-provider production matrix (Phase 3 ships Twilio SMS only; additional providers are later follow-ons).
- AI draft generation, prompt orchestration, validator wiring, and AI-disclosure generation logic (Phase 4).
- Knowledge-axis RAG/manual/persona runtime integration (Phase 5).
- Autonomous sends, auto-approval, or removal of countdown (forbidden by ADR-005/013 and BASELINE inviolables).
- Multi-tenant/channel partitioning strategy redesign (deferred).

## 4. Story breakdown (filled later by PM)

| # | Story | Estimate | Depends on | Status |
|---|---|---|---|---|
| 3.1 | Phase 3 entry gate + compliance envelope + secrets/bootstrap preflight | 2h | — | done |
| 3.2 | Adapter boundary hardening + contract conformance suite (Twilio + Echo fixture) | 3h | 3.1 | planned |
| 3.3 | Inbound webhook endpoint + authenticity checks + Inbox/Identity/Conversation defaults | 3h | 3.2 | planned |
| 3.4 | Idempotency/replay controls (inbound + outbound) + action-key contract | 2h | 3.2, 3.3 | planned |
| 3.5 | Outbound Twilio execution + Oban retry/terminal failure semantics | 3h | 3.4 | planned |
| 3.6 | Compensation invocation operator flow + countdown parity | 2h | 3.5 | planned |
| 3.7 | `AuditLive.Chain` admin viewer + policy gate | 3h | 3.4, 3.5 | planned |
| 3.8 | Webhook throttle + deployer docs + phase integration/regression gate | 3h | 3.1-3.7 | planned |

## 5. Dependencies

### External

- Twilio account and sandbox credentials for SMS delivery + webhook verification.
- Twilio webhook signing requirements and test fixtures.
- Deployer-specific legal/compliance constraints for SMS in target geography.

### Internal

- Phase 2 shipped chain and safety controls are baseline requirements, not optional inputs.
- ADR-005 (human approval), ADR-013 (countdown), ADR-016 (four-stage chain) remain binding.
- Phase 2 deferred commitments now in-scope for this phase: compensation invocation UI and TO-14 audit viewer.

## 6. Risks

- Compliance constraints for SMS may require stricter send windows/content controls than current defaults.
  - Mitigation: treat compliance constraints as explicit design inputs in story 3.1 and enforce through testable acceptance criteria.
- Real outbound side effects can violate safety constraints if bypass paths appear.
  - Mitigation: regression tests proving approval/countdown/audit still gate all sends.
- Inbound identity matching can create incorrect records if placeholder/ambiguity handling is weak.
  - Mitigation: explicit defaults in ACs + deterministic auditable triage path.
- Webhook replay/duplication can corrupt chain semantics.
  - Mitigation: explicit idempotency key contract + duplicate-delivery tests.
- Public webhook surface can be abused.
  - Mitigation: endpoint throttling, authenticity checks, and preflight-verified deployer configuration.
- Secret/config handling may leak credentials or raw payloads in logs.
  - Mitigation: environment-based secret loading + redaction requirements + tests/assertions around sensitive logging.

## 7. Open questions

- [x] First real provider/channel for Phase 3: **Twilio SMS** (resolved).
- What are the non-negotiable compliance constraints for Twilio SMS in the first target deployment (allowed message windows, consent prerequisites, template/pre-approval rules)?
- What retry envelope for outbound failures is required for regulated-service operations (max attempts, backoff class, terminal-state behavior)?
- What deduplication contract is required for inbound webhooks (provider delivery id vs computed hash vs both), and what retention window is required?
- For unknown inbound identifiers, what placeholder identity naming/status policy should be the framework default wording (before deployer override)?

## 8. Safety review

- **AGENTS §7.1 — No AI domain assertions without validation**
  - Phase 3 coverage: N/A for generation path (AI draft generation remains Phase 4). No new AI-output assertion surface is introduced in this phase.

- **AGENTS §7.2 — Human-in-the-loop for ALL sends**
  - Phase 3 coverage: preserved. Twilio outbound execution still requires explicit operator approval and server-side 5-second countdown; compensation invocation follows the same rule.

- **AGENTS §7.3 — Audit trail mandatory**
  - Phase 3 coverage: preserved and extended. Outbound real-send transitions, compensation sends, and inbound webhook processing must produce auditable events and remain verifiable via `mix audit.verify` semantics.

- **AGENTS §7.4 — Sensitive data handling**
  - Phase 3 coverage: inbound payload identifiers/content are treated as sensitive; provider auth credentials are never persisted in business/audit rows; raw payload logging must be redacted.

- **AGENTS §7.5 — Disclosure**
  - Phase 3 coverage: honest-framing guard remains enforced for compensation/safety copy. AI-assistance disclosure remains N/A until Phase 4 AI draft generation.
