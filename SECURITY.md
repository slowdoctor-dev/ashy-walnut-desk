# Security Policy

## Reporting a vulnerability

If you discover a security vulnerability, please email the maintainer
**privately**:

📧 [Contact via GitHub profile]

Do **NOT** open a public GitHub issue for security vulnerabilities.

### What to include

- Type of vulnerability (e.g., auth bypass, PII leak, injection)
- Affected version / commit
- Steps to reproduce
- Potential impact
- Any proposed mitigation

### Response timeline

- **24 hours**: acknowledgment of receipt
- **7 days**: initial assessment
- **30 days**: targeted resolution

This is a solo-developer alpha project. Timeline is best-effort.

## Safety-critical concerns

If you discover a defect that could harm end users in a deployment (e.g.,
guardrail bypass, auto-send bug, audit trail gap):

1. Treat it as a security issue (private report first)
2. Do not deploy the affected version
3. Notify deployment operators if you're running it in production

## Scope

In scope:
- Authentication / authorization bypass
- PII leakage
- Audit trail gaps
- Safety guardrail bypass
- Webhook signature verification flaws
- LLM prompt injection enabling auto-send
- SQL injection (despite Ash protections)
- XSS in LiveView

Out of scope:
- Issues only reproducible in self-modified forks
- Performance issues (unless DoS-level)
- Theoretical vulnerabilities without working exploit

## Known limitations

This software is **alpha**. Until v1.0:
- Not certified for any regulated production use
- Not audited by a security firm
- API may break between versions
- No backwards-compatibility guarantee

See [`DISCLAIMER.md`](DISCLAIMER.md) for full warranty disclaimers.
