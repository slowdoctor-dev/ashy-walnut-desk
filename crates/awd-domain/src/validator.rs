//! Safety-validator result types. Ports `safety/validator_result.ex`.
//!
//! The validator *rules* (regexes) live in the `awd-safety` crate; these are
//! the shared result/violation shapes plus the composite "passed?" rule: a
//! result passes iff it has no `error`-severity violations (warnings don't
//! block approval).

/// Only `Error` violations block approval; `Warning`s are advisory.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

/// A single rule violation. `span` is an optional `(start, end)` char range
/// into the checked text; `locale_key` is the i18n key for the message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Violation {
    pub code: String,
    pub severity: Severity,
    pub span: Option<(usize, usize)>,
    pub locale_key: String,
}

/// Result of running the validator stack over a piece of text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidatorResult {
    pub passed: bool,
    pub violations: Vec<Violation>,
    pub baseline_version: String,
    pub deployment_version: Option<String>,
}

impl ValidatorResult {
    /// The composite pass rule: no `Error`-severity violation present.
    pub fn passes(violations: &[Violation]) -> bool {
        !violations.iter().any(|v| v.severity == Severity::Error)
    }

    /// Build a result, computing `passed` from the violations.
    pub fn new(
        violations: Vec<Violation>,
        baseline_version: String,
        deployment_version: Option<String>,
    ) -> Self {
        let passed = Self::passes(&violations);
        Self {
            passed,
            violations,
            baseline_version,
            deployment_version,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(sev: Severity) -> Violation {
        Violation {
            code: "c".into(),
            severity: sev,
            span: None,
            locale_key: "k".into(),
        }
    }

    #[test]
    fn passes_with_no_violations_or_only_warnings() {
        assert!(ValidatorResult::passes(&[]));
        assert!(ValidatorResult::passes(&[
            v(Severity::Warning),
            v(Severity::Warning)
        ]));
    }

    #[test]
    fn fails_with_any_error_violation() {
        assert!(!ValidatorResult::passes(&[
            v(Severity::Warning),
            v(Severity::Error)
        ]));
        let r = ValidatorResult::new(vec![v(Severity::Error)], "v2-abc".into(), None);
        assert!(!r.passed);
    }
}
