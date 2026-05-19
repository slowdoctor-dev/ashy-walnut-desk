# Contributing to ashy-walnut-desk

## Status

This project is in **alpha** and primarily developed by a solo maintainer.
External contributions are welcome but response may be slow.

## Before contributing

1. Read [`AGENTS.md`](AGENTS.md) — universal agent instructions
2. Read [`BASELINE.md`](BASELINE.md) — all major decisions
3. Read [`docs/methodology.md`](docs/methodology.md) — SDD workflow
4. Browse [`specs/`](specs/) — the current spec state

## How to contribute

### Bug reports

Open a GitHub issue with:
- Steps to reproduce
- Expected vs actual behavior
- Elixir/Erlang/OS versions
- Relevant logs (with PII redacted)

### Feature requests

Open a GitHub issue tagged `feature-request`. Note: feature work happens
via the SDD process. New features become stories in a phase, not direct
PRs.

### Code contributions

1. Pick a story from `specs/phase-N/stories/` with status `ready`
2. Open an issue saying "I'm starting story N.M" so we can claim it
3. Branch: `feature/story-N.M-short-slug`
4. Use the GSD workflow (`prompts/gsd-execute-story.md`)
5. One PR per story; squash-merge
6. Commit format: `[N.M] description`
7. `just verify` must pass

### Spec contributions

Improvements to specs/, ADRs, prompts/, or docs/ are very welcome.

Process:
1. Open an issue describing the change
2. Reference the affected spec file(s)
3. Open a PR with the change + reasoning
4. If it's an ADR, add to the index in `specs/decisions/README.md`

## What we won't accept

- PRs without a corresponding story
- Multiple unrelated changes in one PR
- Code without tests (where testable)
- Hardcoded user-facing strings (use gettext)
- Direct Ecto queries bypassing Ash
- Auto-sending behavior (human approval is mandatory)
- Real customer/client data in tests or fixtures

## Safety review

This software is intended for regulated-service contexts. Any change
that touches sensitive records, AI output, or send paths gets extra
scrutiny:

- Safety review section in the story (required)
- Reviewer flagged per `specs/compliance/`
- All ACs include the audit/guardrail/countdown checks

If unsure whether a change has safety implications, ask.

## Code of conduct

See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## License

By contributing, you agree your contributions are licensed under the
Apache License 2.0 (see [`LICENSE`](LICENSE)).
