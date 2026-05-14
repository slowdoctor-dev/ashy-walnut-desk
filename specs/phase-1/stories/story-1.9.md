# Story 1.9: Playwright screenshot evidence for Identity timeline UX

**Phase**: 1
**Estimate**: 2h
**Depends on**: 1.6
**Status**: done

---

## Goal

Add reproducible Playwright screenshot capture for key Identity timeline UI states and commit evidence under `docs/phase-1-screenshots/`.

## Context

Phase 1 AC13 requires both automated LiveView integration tests and reproducible visual evidence generated via `just` workflow.

## Reference specs

- `/AGENTS.md` §5 (commands/workflow discipline)
- `/specs/phase-1/requirements.md` §2 (AC13)
- `/specs/phase-1/architecture.md` §2 (Tooling) and §11 (Manual/Playwright)

## Acceptance criteria

- [x] AC1: `just screenshots` recipe exists and generates deterministic timeline-state screenshots against a running dev server. — Verify: `just screenshots`
- [x] AC2: `docs/phase-1-screenshots/` contains committed screenshots covering create state and linked-record timeline state. — Verify: `ls -1 docs/phase-1-screenshots`
- [x] AC3: A short doc note describes how to regenerate screenshots locally. — Verify: `grep -q "just screenshots" README.md`

## Files to create

```
docs/phase-1-screenshots/*   — committed screenshot evidence
scripts/screenshots-phase1.sh   — reproducible capture script (or equivalent)
```

## Files to modify

```
justfile   — add screenshots recipe
README.md   — add screenshot regeneration instructions
```

## Implementation notes

Keep screenshot generation deterministic and scriptable; avoid manual-only ad-hoc capture steps.

## Safety review

- Sensitive records touched? Uses fake fixture data only.
- AI output to end user possible? No.
- Guardrails applied? N/A.
- Audit trail covered? N/A.

## Out of scope (will NOT do in this story)

- Functional integration assertions: deferred to 1.10
- CI visual diff gate: deferred to future hardening story

## Verification

```bash
just verify
just screenshots
ls -1 docs/phase-1-screenshots
```

## Notes during implementation

- Decisions made:
  - **Auth**: real magic-link flow via `/dev/mailbox` (no dev-only auto-login plug, no production-touching code). Magic-link request and confirm are LiveView forms (`phx-submit`); to avoid the LV-vs-WebSocket race the script POSTs directly to `/auth/user/magic_link/request` and `/auth/user/magic_link` using the page's CSRF token, then navigates the browser context so the resulting session cookie sticks.
  - **Idempotency**: seed task is find-or-create on the admin user (with role re-promotion) and append-fresh on the Identity + timeline records. Capture script picks the most recently created Identity by display name (`Aria Demo`).
  - **Capture set**: 3 screenshots — `01-identities-index.png` (create surface), `02-identity-show-timeline.png` (read surface — merged Event + Appointment + Note timeline), `03-identity-show-record-event-form.png` (write surface — inline Record-event form expanded).
  - **Script language**: Python 3 + `playwright` (already installed, zero new repo deps). One Python file (`scripts/screenshots-phase1.py`) shelled in from `scripts/screenshots-phase1.sh` (server-up check + seed + capture).
  - **Demo data live in dev DB only**: capture is run against `mix phx.server` in dev env; the seed task is namespaced under `Mix.Tasks.Phase1.Demo.Seed` to make its dev-only intent obvious.
- Spec drift noticed:
  - **Pre-existing 1.6 bug uncovered by the capture**: `IdentityLive.Index.archived?/1` returned the strings `"true"`/`"false"` to feed `data-archived={…}`, but the same helper was reused in `:if={archived?(identity)}` — the string `"false"` is truthy in Elixir, so every row rendered an "ARCHIVED" badge regardless of `deleted_at`. Fixed inline (1-line: helper returns booleans; the data attribute now wraps with `to_string/1`). The 1.6 LiveView tests didn't catch this because they don't assert on the badge in non-archived rows.
- Gotchas to add to AGENTS.md §10:
  - LiveView `phx-submit` forms cannot be reliably driven from headless scripts via click/`requestSubmit` — the WebSocket-vs-page-load race causes the form event to be lost. Direct-POST to the form's `action` URL with the page's CSRF token (read from `<meta name="csrf-token">` and the form's hidden `_csrf_token` input) is the script-friendly path.
  - Returning `"true"`/`"false"` strings from a render helper that's also fed to `:if={…}` is a silent-truthy footgun. Helpers used in both `data-*` attributes and `:if` conditions should return booleans; convert to strings at the data-attribute boundary with `to_string/1`.
