# Phase 4 — Requirements

## 1. Goal

Deliver safe AI-assisted draft generation for the existing Interaction chain so operators can generate, review, revise, and approve drafts without bypassing human judgment, countdown, or audit invariants.

## 2. Acceptance criteria (phase-level)

- [ ] `just verify` is green after all Phase 4 stories merge.
- [ ] Operator/admin can invoke AI draft generation for an Inbox through named Ash actions only (no direct model call from LiveView event handlers).
- [ ] Generated draft content persists in `Draft` with full provenance fields (`ai_prompt`, `ai_model`, `ai_response`, `ai_validator_output`) and all are audit-trail visible to admin policies.
- [ ] AI-generated output never sends directly; all outbound delivery still requires explicit human approval + server-side 5-second countdown from Phase 2/3.
- [ ] Safety validation runs on every AI generation attempt before content is considered ready for approval, with deterministic pass/fail outcomes captured in `ai_validator_output`.
- [ ] If validation fails, send path remains blocked until an operator revises/regenerates to a valid state.
- [ ] AI-assisted disclosure text is appended/persisted in the operator-visible draft output according to deployment-configurable wording (no hardcoded domain claims).
- [ ] Prompt assembly uses only approved context sources (Identity + Conversation/Inbox context + Knowledge resources), with explicit exclusion of secrets/credentials from prompt payloads.
- [ ] Prompt assembly emits stable provider-compatible prompt-caching markers so cache behavior can be enabled without changing business semantics.
- [ ] Prompt/response persistence honors sensitive-data policies (no viewer exposure of sensitive draft/AI fields; admin/operator visibility only per policy).
- [ ] AI provider failures/timeouts degrade gracefully: generation fails with actionable operator feedback and no partial send-side state mutation.
- [ ] Regeneration creates auditable supersession semantics (old draft/history remains traceable; no destructive overwrite that erases prior model output).
- [ ] All AI-generated outbound-facing copy (primary draft body and compensation body) remains honest-framing compliant and continues to require explicit human-triggered send flow from Phase 2/3.

## 3. Scope

### In scope

- AI draft generation entry points for operator/admin on existing Inbox/Draft flow.
- Manual AI generation trigger model only (operator/admin initiated from UI/action flow).
- Prompt assembly from approved system context (Identity, Interaction history, Knowledge artifacts, Persona/guardrail inputs).
- Prompt-caching posture for Anthropic-compatible calls using stable cache markers in prompt assembly.
- Persisted AI provenance fields on `Draft` and policy-safe exposure in LiveView surfaces.
- Safety-validator integration for generated content with deterministic blocking behavior.
- Disclosure footer/text requirement for AI-assisted drafts.
- Regenerate/revise workflow semantics with audit continuity.
- Failure handling for model/network/rate-limit errors (operator-visible, non-destructive).
- Regression protection for Phase 2/3 invariants: no autonomous send, countdown preserved, audit chain intact.

Safety implications in scope:
- AI output can contain unsafe domain assertions; validator gate must be mandatory before approval readiness.
- Prompt/response bodies can contain sensitive data; policy + logging posture must prevent viewer leakage and log exfiltration.
- Human-in-the-loop boundaries must remain server-authoritative, not UI-only.
- Validator/user-facing failure messages must be gettext-backed (no hardcoded operator-facing strings).

### Out of scope

- New channel/provider integrations (Twilio remains the only concrete real adapter in current scope).
- Knowledge-axis retrieval architecture expansion (full pgvector/RAG tuning belongs to Phase 5).
- Autonomous/auto-send behavior, auto-approval, or countdown removal.
- Auto-generate-on-inbound-arrival behavior (deferred; Phase 4 generation is manual-trigger only).
- Deployment-jurisdiction legal/compliance content authoring (deployer responsibility under `specs/compliance/`).
- Multi-tenant partitioning redesign.

## 4. Story breakdown (filled later by PM)

| # | Story | Estimate | Depends on | Status |
|---|---|---|---|---|
| 4.1 | Persona foundation (Knowledge domain + resource + admin surface skeleton) | 2h | — | planned |
| 4.2 | AI subsystem skeleton (adapter contract + fixture + prompt/response + assembler) | 3h | 4.1 | planned |
| 4.3 | Anthropic Req adapter + config/allowlist + conformance tests | 3h | 4.2 | planned |
| 4.4 | Safety validator stack (baseline + honest-framing runtime + composite wiring) | 3h | 4.2 | planned |
| 4.5 | Draft generation state machine + worker-gated actions + audit events | 3h | 4.1, 4.4 | planned |
| 4.6 | Oban generation worker orchestration + telemetry + failure semantics | 3h | 4.3, 4.4, 4.5 | planned |
| 4.7 | InboxLive generation UX (panel, validator badge, candidate flow, gettext errors) | 3h | 4.5, 4.6 | planned |
| 4.8 | Phase 4 preflight + deployer docs + integration/regression gate | 3h | 4.1-4.7 | planned |

## 5. Dependencies

### External

- Anthropic API credentials and quota for the selected model(s).
- Deployer-approved disclosure wording and regulated-language constraints.
- Deployer-provided compliance/guardrail documents used by validator and prompt context.

### Internal

- Phase 2 chain semantics (`Inbox -> Draft -> Action -> Compensation`) and approval/countdown model.
- Phase 3 real adapter + inbound/outbound reliability/audit behavior as baseline.
- Existing Identity + Interaction + Knowledge resource policies and paper-trail posture.

## 6. Risks

- Vague safety criteria may produce inconsistent validator outcomes.
  - Mitigation: define deterministic validator result schema and explicit blocking rules in AC-backed tests.
- Prompt context bloat or wrong context selection may degrade output quality or leak unnecessary sensitive data.
  - Mitigation: explicit context allowlist + size/selection rules + tests for excluded fields.
- Operators may over-trust model output in regulated contexts.
  - Mitigation: mandatory disclosure + preserved manual revise/approve flow + no direct send capability.
- Provider outages or latency spikes may stall frontline work.
  - Mitigation: fail-fast generation UX and manual drafting fallback with no chain corruption.
- Regeneration semantics can accidentally overwrite forensic history.
  - Mitigation: enforce append/supersede audit semantics; prohibit destructive mutation of prior AI outputs.
- Validator false-negatives may block legitimate operator communication unnecessarily.
  - Mitigation: define explicit policy for audited operator override vs strict no-override, with measurable review/triage loop.

## 7. Open questions

- What is the exact validator contract for Phase 4 MVP: pass/fail only, or pass/fail + categorized violation codes that drive UI hints?
- Should AI generation be allowed for viewers in read-only preview mode, or strictly operator/admin only in Phase 4?
- What is the required freshness/window for conversation context included in prompts (last message, last N messages, full thread)?
- Should disclosure text be immutable per deployment config at generation time, or editable by operator before approval?
- For regenerate behavior, should the previous draft be automatically superseded, or should multiple candidate drafts coexist until explicit operator selection?
- Which model(s) are allowed for Phase 4 launch, and is model selection operator-configurable or deployment-fixed?
- What minimum telemetry is required for AI operations (latency, token usage, validator failure rates) before Architect finalization?
- Should Phase 4 use `ash_ai` primitives directly or keep Req-direct Anthropic calls with an internal adapter boundary?
