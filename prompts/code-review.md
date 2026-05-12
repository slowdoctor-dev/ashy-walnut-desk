# Code Review Prompt

> Use after a story is implemented but before merging.
> Works with any AI coding agent.

---

You are reviewing code for ashy-walnut-desk. This is safety-sensitive
software for regulated-service contexts — safety findings override
everything else.

## Step 0: Load context

Read in order:
1. `/AGENTS.md`
2. `/BASELINE.md`
3. The story being reviewed: `/specs/phase-N/stories/story-N.X.md`
4. The PR diff (or local uncommitted changes)

## Review across 9 axes

For each axis: PASS / WARN / FAIL with specific findings.

### 1. Architecture
- Adheres to three-axis model? (`/specs/architecture.md`)
- Layer violations? (UI → Domain → Data)
- Ash patterns correctly used?
- Module boundaries respected?

### 2. Security
- Authentication on every endpoint?
- Authorization via Ash policies (no public-by-default)?
- PII handled (sensitive identifiers hashed, sensitive fields marked)?
- Secrets via env vars (no hardcoded keys)?
- XSS in LiveView templates?
- CSRF tokens present?
- Webhook signatures verified?

### 3. Safety (CRITICAL — overrides others)
- AI output guardrails applied?
- Human-approval enforced (5-second countdown)?
- AshPaperTrail on sensitive-record resources?
- Deployment-specific compliance respected (see `specs/compliance/`)?
- Tone/terminology per active Persona?
- No unvalidated domain assertions in AI prompts?

### 4. Performance
- N+1 queries in Ash relationships?
- Missing indices?
- Blocking operations in LiveView mount?
- Memory leaks (GenServer state)?

### 5. Test Coverage
- Unit tests on Ash actions?
- Integration tests on LiveView flows?
- AI evaluation tests for AI-touching code?
- Edge cases covered?
- No real customer/client data in fixtures?

### 6. Internationalization
- Hardcoded user-facing strings? (must use gettext)
- Locale completeness for the deployment?
- Tone consistency per active Persona?

### 7. Code Quality
- Naming conventions?
- Function length reasonable (< 30 lines preferred)?
- Module organization?
- Documentation (@moduledoc, @doc)?
- Inappropriate abstractions?
- Dead code?

### 8. Ash Best Practices
- Resource structure (attributes, relationships, actions, policies in order)?
- Action design (intent-revealing names, not CRUD)?
- Policy completeness?
- Migration cleanliness?
- Extension usage (AshPaperTrail where required)?
- No bypassing Ash (no raw `Ecto.Repo`)?

### 9. Spec Drift
- Code matches story requirements + acceptance criteria?
- Spec needs updating to match new reality?
- Undocumented behavior?
- Missing ADRs for architectural decisions?
- STATUS updated in story file?

## Output format

```
## Code Review Summary

Story: N.X — <title>
Total findings: N (Critical: X, High: Y, Medium: Z, Low: W)

### Blockers (must fix before merge)
1. [axis] <finding> — fix: <suggestion>

### Recommendations
1. [axis] <finding> — fix: <suggestion>

### Approval Status
- [ ] Ready to merge
- [x] Needs fixes (see blockers)
```

## Critical rules

- ALL 9 axes must be reviewed
- Critical/High findings block merge
- Safety findings (axis 3) override all others
- If you can't review an axis (not applicable), say so explicitly

---

Begin: which story / PR are you reviewing?
