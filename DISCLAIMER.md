# Disclaimer

## ⚠️ Important Notice

**ashy-walnut-desk** is an experimental, alpha-stage open-source software
project. It is **NOT** certified, approved, or validated for use in any
regulated setting in any jurisdiction.

## Not a Certified Product

This software has not been reviewed or certified by any regulatory body
in any jurisdiction. It is not a regulated medical device, a regulated
financial-services product, or a regulated legal-services product. It is
software infrastructure that a deployer chooses how to use.

## No Warranty

THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES, OR OTHER LIABILITY ARISING FROM, OUT OF, OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Deployer Responsibility

If you choose to use this software in any production setting, you are
solely responsible for:

1. **Regulatory compliance** in your jurisdiction, including but not
   limited to: industry-specific licensing laws, data-protection laws
   (GDPR / CCPA / PIPA / HIPAA / etc.), and advertising or marketing
   regulations applicable to your domain.

2. **End-user safety** including:
   - Verification of all AI-generated content before delivery
   - Maintaining human oversight on every customer/client interaction
   - Following the standards of your profession or industry
   - Reporting incidents to relevant authorities

3. **Data security** including:
   - Encryption at rest and in transit
   - Access controls and audit trails
   - Backup and disaster recovery
   - Incident response procedures

4. **Domain validation** for any specialized workflow:
   - Independent review by qualified professionals in your domain
   - Local ethics or oversight committee review where applicable
   - Pilot evaluation appropriate to your use case

## AI-Generated Content Warning

This software uses Large Language Models (by default, Anthropic's Claude)
to generate message drafts. AI-generated content:

- **MAY contain factual errors** ("hallucinations")
- **MAY misinterpret context** or end-user intent
- **MAY produce inappropriate domain statements** despite guardrails
- **MUST be reviewed by qualified human operators** before sending
- **MUST NOT replace professional judgment** in regulated domains

The 5-second countdown and human-approval workflow is the primary
safety mechanism, not the AI guardrails alone.

## End-User Data Considerations

This software processes end-user communications. Important considerations:

- **Sensitive identifiers** (phone, email) can be hashed before storage
  (deployer configures)
- **Names and similar PII** can be marked as sensitive fields
- **Message content** is logged for audit purposes
- **External LLM use** means message content is transmitted to a
  third-party service; deployer is responsible for the legality of
  this transfer in their jurisdiction
- Deployers **MUST** obtain appropriate consent from end users for
  AI-assisted communication and any cross-border data transfer

## No Professional Relationship

Use of this software does **not** establish any professional or fiduciary
relationship between:
- The software authors and any deployer
- The software authors and any end user
- The LLM provider and any end user

## License & Liability Limitation

This software is licensed under the Apache License, Version 2.0 (see [LICENSE](LICENSE)).
By using this software, you accept all risks associated with its use.

## Reporting Concerns

1. **Critical security**: report privately (see SECURITY.md)
2. **General issues**: open a GitHub issue
3. **Safety concerns**: open a GitHub issue with `safety` label

## Contact

Repository: see project home

---

**Last updated**: 2026-05
**Version**: 1.0 (alpha)
