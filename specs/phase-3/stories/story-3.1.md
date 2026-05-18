# Story 3.1: Phase 3 Entry Gate + Compliance Envelope + Secrets/Bootstrap Preflight

**Phase**: 3
**Estimate**: 2h
**Depends on**: —
**Status**: done

---

## Goal

Establish the Phase 3 operational entry gate so Twilio work cannot proceed with missing compliance decisions or invalid runtime/bootstrap configuration.

## Context

Phase 3 introduces real external sends and public webhook intake. Before adapter/inbound/outbound stories, the phase needs an executable preflight and explicit compliance envelope inputs so later stories are deterministic and testable.

## Reference specs

- `/AGENTS.md` §7 Safety Rules (inviolable)
- `/specs/architecture.md` §9 External integrations, §11 Security posture
- `/specs/phase-3/architecture.md` §1 Overview, §2 Affected modules
- `/specs/decisions/ADR-022-twilio-as-first-real-adapter.md`

## Acceptance criteria

- [x] AC1: `mix phase3.webhook.preflight` exists and fails fast (non-zero exit) when required Twilio env vars are missing. — Verify: `mix phase3.webhook.preflight; echo $?` (expect non-zero with missing env)
- [x] AC2: `mix phase3.webhook.preflight` passes when required Twilio env vars and a `twilio-sms` Channel row are present. — Verify: `TWILIO_ACCOUNT_SID=... TWILIO_AUTH_TOKEN=... TWILIO_FROM_NUMBER=... mix phase3.webhook.preflight`
- [x] AC3: Phase 3 compliance envelope decisions are documented in phase specs (send-window policy input, consent prerequisite input, retry envelope input, dedupe retention input). — Verify: `rg -n "send-window|consent|retry envelope|dedupe" specs/phase-3/architecture.md specs/phase-3/requirements.md`
- [x] AC4: Story-level verification gates are documented for later stories (preflight as prerequisite command). — Verify: `rg -n "phase3.webhook.preflight" specs/phase-3/stories/story-3.*.md`

## Files to create

```
lib/mix/tasks/phase3.webhook.preflight.ex   — executable preflight gate for Twilio config + channel bootstrap checks
```

## Files to modify

```
specs/phase-3/architecture.md               — ensure compliance envelope inputs are explicitly captured
specs/phase-3/requirements.md               — keep open questions and AC wording aligned with preflight gate
```

## Implementation notes

Keep this story strictly as a gate. Do not implement webhook routing, adapter execution, or retry logic here. Preflight should validate presence/shape of required config and bootstrap prerequisites only.

## Safety review

- Sensitive records touched? no
- AI output to end user possible? no
- Guardrails applied? N/A
- Audit trail covered? N/A (configuration/tooling story)

## Out of scope (will NOT do in this story)

- Twilio adapter implementation: deferred to story 3.2 and 3.5
- Webhook controller and signature verification: deferred to story 3.3
- Idempotency/replay logic: deferred to story 3.4

## Verification

```bash
just verify
# Plus story-specific:
mix phase3.webhook.preflight
rg -n "phase3.webhook.preflight" specs/phase-3/stories/story-3.*.md
```

## Notes during implementation

(AI fills this in during execution.)

- Decisions made:
- Spec drift noticed:
- Gotchas to add to AGENTS.md §10:
