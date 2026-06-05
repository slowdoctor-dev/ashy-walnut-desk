//! Baseline safety validator — faithful port of
//! `safety/validators/baseline.ex` (+ the folded-in honest-framing check from
//! `safety/honest_framing.ex`).
//!
//! Checks, in order: guarantee claims, diagnostic claims, pricing assertions,
//! prohibited phrases (none by default), length > [`MAX_LENGTH`], then
//! honest-framing banned terms. Every violation is severity `Error`.

use awd_domain::validator::{Severity, ValidatorResult, Violation};
use regex::Regex;
use sha2::{Digest, Sha256};
use std::sync::OnceLock;

pub const MAX_LENGTH: usize = 2_000;

/// No prohibited phrases ship by default (deployers add their own).
pub const PROHIBITED_PHRASES: &[&str] = &[];

/// Pattern *source* strings — kept byte-identical to the Elixir `Regex.source`
/// values so the version hash and matching behavior stay aligned. The `(?i)`
/// flag is applied per-pattern to match each Elixir regex's `/i` (or absence).
pub const GUARANTEE_PATTERNS: &[&str] = &[
    r"\bi guarantee\b",
    r"\bwe guarantee\b",
    r"\bwe promise\b",
    r"\bguaranteed\b",
];

pub const DIAGNOSTIC_PATTERNS: &[&str] = &[
    r"\bdiagnosis\b",
    r"\bi diagnose\b",
    r"\byou (have|are experiencing)\b",
    r"\bdefinitely (have|are)\b",
];

/// Note: pattern 0 is case-sensitive in Elixir (no `/i`); 1 and 2 are `/i`.
pub const PRICING_PATTERNS: &[&str] = &[
    r"\$\s?\d+(?:[\.,]\d{2})?",
    r"\busd\s?\d+(?:[\.,]\d{2})?",
    r"\b\d+(?:[\.,]\d{2})?\s?(dollars|usd)\b",
];

/// `safety/honest_framing.ex` banned terms (substring, case-insensitive).
pub const HONEST_FRAMING_TERMS: &[&str] = &["unsend", "undo send", "recall message", "take back"];

/// Whether a pricing pattern at this index is case-insensitive in Elixir.
const PRICING_CASE_INSENSITIVE: [bool; 3] = [false, true, true];

fn compiled(set: &'static [&'static str], case_insensitive: bool) -> Vec<Regex> {
    set.iter()
        .map(|src| {
            regex::RegexBuilder::new(src)
                .case_insensitive(case_insensitive)
                .build()
                .expect("baseline regex must compile")
        })
        .collect()
}

fn guarantee_re() -> &'static [Regex] {
    static RE: OnceLock<Vec<Regex>> = OnceLock::new();
    RE.get_or_init(|| compiled(GUARANTEE_PATTERNS, true))
}

fn diagnostic_re() -> &'static [Regex] {
    static RE: OnceLock<Vec<Regex>> = OnceLock::new();
    RE.get_or_init(|| compiled(DIAGNOSTIC_PATTERNS, true))
}

fn pricing_re() -> &'static [Regex] {
    static RE: OnceLock<Vec<Regex>> = OnceLock::new();
    RE.get_or_init(|| {
        PRICING_PATTERNS
            .iter()
            .enumerate()
            .map(|(i, src)| {
                regex::RegexBuilder::new(src)
                    .case_insensitive(PRICING_CASE_INSENSITIVE[i])
                    .build()
                    .expect("pricing regex must compile")
            })
            .collect()
    })
}

fn any_match(text: &str, patterns: &[Regex]) -> bool {
    patterns.iter().any(|re| re.is_match(text))
}

fn violation(code: &str) -> Violation {
    Violation {
        code: code.to_string(),
        severity: Severity::Error,
        span: None,
        locale_key: format!("validator.violations.{code}"),
    }
}

/// The honest-framing substring check. Returns the first banned term hit.
pub fn honest_framing_hit(text: &str) -> Option<&'static str> {
    let lower = text.to_lowercase();
    HONEST_FRAMING_TERMS
        .iter()
        .find(|term| lower.contains(*term))
        .copied()
}

fn has_prohibited_phrase(text: &str) -> bool {
    let lower = text.to_lowercase();
    PROHIBITED_PHRASES
        .iter()
        .any(|p| lower.contains(&p.to_lowercase()))
}

/// Run the baseline validator over `text`.
pub fn check(text: &str) -> ValidatorResult {
    let mut violations: Vec<Violation> = Vec::new();

    if any_match(text, guarantee_re()) {
        violations.push(violation("guarantee_claim"));
    }
    if any_match(text, diagnostic_re()) {
        violations.push(violation("diagnostic_claim"));
    }
    if any_match(text, pricing_re()) {
        violations.push(violation("pricing_assertion"));
    }
    if has_prohibited_phrase(text) {
        violations.push(violation("prohibited_phrase"));
    }
    // Elixir `String.length/1` counts graphemes; we count Unicode scalars.
    // Equivalent for all non-combining text (message bodies are also DB-capped
    // at 2000). Documented divergence on exotic grapheme clusters only.
    if text.chars().count() > MAX_LENGTH {
        violations.push(violation("length_exceeded"));
    }
    if honest_framing_hit(text).is_some() {
        violations.push(violation("honest_framing"));
    }

    ValidatorResult::new(violations, version().to_string(), None)
}

/// Rust-native deterministic baseline version. Elixir used
/// `sha256(:erlang.term_to_binary(rule_signature))`, which can't be reproduced;
/// we hash a canonical string encoding of the same rule signature. The `"v2-"`
/// prefix marks it as deliberately non-comparable to the old Elixir versions.
pub fn version() -> &'static str {
    static V: OnceLock<String> = OnceLock::new();
    V.get_or_init(|| {
        // Unit separator between list items; newline between fields.
        let join = |items: &[&str]| items.join("\u{1f}");
        let mut prohibited: Vec<&str> = PROHIBITED_PHRASES.to_vec();
        prohibited.sort_unstable();
        let mut terms: Vec<&str> = HONEST_FRAMING_TERMS.to_vec();
        terms.sort_unstable();

        let canonical = format!(
            "max_length={}\nprohibited_phrases={}\nguarantee_patterns={}\ndiagnostic_patterns={}\npricing_patterns={}\nhonest_framing_terms={}",
            MAX_LENGTH,
            join(&prohibited),
            join(GUARANTEE_PATTERNS),
            join(DIAGNOSTIC_PATTERNS),
            join(PRICING_PATTERNS),
            join(&terms),
        );

        let mut hasher = Sha256::new();
        hasher.update(canonical.as_bytes());
        format!("v2-{}", hex::encode(hasher.finalize()))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn codes(r: &ValidatorResult) -> Vec<String> {
        r.violations.iter().map(|v| v.code.clone()).collect()
    }

    #[test]
    fn clean_text_passes() {
        let r = check("Thanks for reaching out — happy to help you book a visit.");
        assert!(r.passed, "violations: {:?}", codes(&r));
        assert!(r.violations.is_empty());
        assert!(r.baseline_version.starts_with("v2-"));
        assert_eq!(r.deployment_version, None);
    }

    #[test]
    fn guarantee_claims_fail() {
        for t in [
            "I guarantee results",
            "We promise a refund",
            "It's guaranteed",
        ] {
            let r = check(t);
            assert!(!r.passed, "{t:?} should fail");
            assert!(codes(&r).contains(&"guarantee_claim".to_string()), "{t:?}");
        }
    }

    #[test]
    fn diagnostic_claims_fail() {
        let r = check("You have an infection and definitely are at risk");
        assert!(!r.passed);
        assert!(codes(&r).contains(&"diagnostic_claim".to_string()));
    }

    #[test]
    fn pricing_assertions_fail_and_case_sensitivity_matches() {
        assert!(!check("The total is $40.00").passed);
        assert!(!check("about USD 25").passed);
        assert!(!check("around 30 dollars").passed);
        // pattern 0 ($...) is case-sensitive but '$' has no case; still matches.
        assert!(check("no prices mentioned here").passed);
    }

    #[test]
    fn length_limit_enforced() {
        let ok = "a".repeat(MAX_LENGTH);
        assert!(check(&ok).passed);
        let too_long = "a".repeat(MAX_LENGTH + 1);
        assert!(!check(&too_long).passed);
        assert!(codes(&check(&too_long)).contains(&"length_exceeded".to_string()));
    }

    #[test]
    fn honest_framing_terms_fail_case_insensitively() {
        for t in [
            "Click to UNSEND",
            "you can undo send",
            "Recall Message now",
            "take back",
        ] {
            let r = check(t);
            assert!(!r.passed, "{t:?} should fail");
            assert!(codes(&r).contains(&"honest_framing".to_string()), "{t:?}");
        }
        assert_eq!(honest_framing_hit("please unsend it"), Some("unsend"));
        assert_eq!(honest_framing_hit("all good"), None);
    }

    #[test]
    fn version_is_stable_and_prefixed() {
        assert_eq!(version(), version());
        assert!(version().starts_with("v2-"));
        assert_eq!(version().len(), 3 + 64);
    }

    #[test]
    fn violation_order_matches_elixir() {
        // guarantee + pricing + honest_framing all present → that relative order.
        let r = check("I guarantee it costs $5 — you can unsend later");
        let c = codes(&r);
        let gi = c.iter().position(|x| x == "guarantee_claim").unwrap();
        let pi = c.iter().position(|x| x == "pricing_assertion").unwrap();
        let hi = c.iter().position(|x| x == "honest_framing").unwrap();
        assert!(gi < pi && pi < hi);
    }
}
