# Domain Models (Three Axes)

This directory holds resource specifications organized along the three
axes of the system. These accumulate THROUGH phases — early phases fill
the "who/when" axis, later phases fill "how" and "what".

```
domain/
├── identity/         — Who/When (customer/client records, encounters, consent)
├── interaction/      — How (conversation, message, channel, draft, audit)
└── knowledge/        — What (manuals, guardrails, personas, references)
```

These directory names are conventions; rename to match the deployment's
language (e.g., `crm/comm/knowledge` for some, `clients/cases/playbook`
for others). The three-axis structure is what matters.

## When to write specs here

- During phase Architect work, write resource specs as `<resource>.spec.md`
- Reference these from phase architecture documents
- Update when the model evolves (in the same commit as code changes
  — see AGENTS.md §9)

## Spec file format

One resource per spec file. Each spec covers:

- Attributes (name, type, sensitive flag, defaults)
- Relationships (belongs_to, has_many, many_to_many)
- Actions (named operations with validations and side effects)
- Policies (who can do what)
- Extensions used (audit trail, soft-delete, versioning)
- Migration notes (snapshots, retention)

Keep specs concise and scannable. The framework's Ash resources are
declarative; the spec mirrors that style.

## Why three axes

A regulated-service business communication system needs three orthogonal
concerns:

- **Who/When** — identity records and their lifecycle events
- **How** — channels, conversations, drafts, the send pipeline
- **What** — operational knowledge that informs replies

Mixing these axes creates god-objects. Keeping them separate keeps each
testable, each replaceable, and each auditable. See `specs/architecture.md`
for the full architectural rationale.
