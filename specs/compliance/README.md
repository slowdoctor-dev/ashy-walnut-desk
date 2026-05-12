# Compliance

This directory documents the compliance posture for a given deployment.
The framework provides hooks; the specific regulations are
**jurisdiction-dependent** and **operator-dependent**.

⚠️ **Nothing in this directory is legal advice.** Each deployment must
have its own legal review before handling real customer/client data.

---

## What lives here

When a deployment fills this directory, expect files like:

- `regulations.md` — applicable laws and what they require
- `privacy.md` — data handling, retention, sub-processor disclosure
- `external-llm.md` — cross-border data transfer policy for AI providers
- `disclosure.md` — what to tell customers about AI assistance
- `data-handling.md` — operational rules for staff and developers
- `legal-consult-log.md` — outcomes of attorney consultations

These are TEMPLATES of common topics. A specific deployment may need
others (sector-specific regulations, audit certifications, etc.) and may
not need all of them.

## Why this directory ships empty

The framework cannot pre-write compliance documents for any single
jurisdiction. A medical clinic in Korea, a law firm in the UK, and a
financial advisor in Singapore all need different documents.

Instead, the framework provides:

- **Audit trail infrastructure** (hash-chained AuditEvent, AshPaperTrail)
- **Approval gating** (5-second countdown before send — see ADR-013)
- **Consent resource type** (versioned, type-enumerated)
- **Sensitive field marking** (`sensitive? true` in Ash resources)
- **Sub-processor list pattern** (Persona/Manual references provider)

The deployment fills the specifics.

## Topics typically covered

A regulated-service deployment usually needs to address:

1. **Sector regulations** — healthcare law, financial regulations, legal
   ethics rules, etc.
2. **Privacy law** — GDPR / PIPA / HIPAA / CCPA / etc., depending on
   jurisdiction and customer location
3. **Cross-border data transfer** — if using a foreign LLM provider,
   review applicable cross-border data rules
4. **AI disclosure** — many jurisdictions require disclosing AI involvement
   in customer communications
5. **Records retention** — how long records must be kept, retention schedules
6. **Incident response** — breach notification timelines and procedures

## What awd CAN'T enforce from software

Compliance is operational, not just technical. The software gates these
behaviors:

- 5-second countdown (ADR-013) prevents some categories of mistakes
- Sensitive field marking prevents accidental log exposure
- Hash-chained audit trail makes tampering detectable
- Auto-appended disclosure footer ensures AI involvement is visible

The software cannot make staff careful. It can only support careful staff.

## Updating this directory

If a law changes or attorney advises differently:

1. Update the relevant document
2. If a software change is needed, file a new story
3. If an ADR is affected, update it (or supersede)
4. Update BASELINE.md §11 if a Cardinal rule changes
5. Document the change reason in CHANGELOG.md

Compliance documents are LIVING. Annual review at minimum.
