//! Composite validator — port of `safety/validators/composite.ex`.
//!
//! Runs the baseline first, then any deployer-supplied validators, aggregating
//! all violations. `passed` is true iff no `Error`-severity violation exists
//! (warnings don't block). Deployment-validator versions are comma-joined into
//! `deployment_version`.

use awd_domain::validator::{ValidatorResult, Violation};

use crate::baseline;

/// Extension point: a deployment adds domain-specific validators (ADR-006).
/// The framework ships none.
pub trait DeploymentValidator {
    fn check(&self, text: &str) -> Vec<Violation>;
    /// Optional immutable version identifier audited alongside the baseline.
    fn version(&self) -> Option<String> {
        None
    }
}

/// Run the baseline + the given deployment validators over `text`.
pub fn check(text: &str, deployment: &[&dyn DeploymentValidator]) -> ValidatorResult {
    let base = baseline::check(text);
    let mut violations: Vec<Violation> = base.violations;
    let mut versions: Vec<String> = Vec::new();

    for validator in deployment {
        violations.extend(validator.check(text));
        if let Some(v) = validator.version() {
            versions.push(v);
        }
    }

    let deployment_version = if versions.is_empty() {
        None
    } else {
        Some(versions.join(","))
    };

    ValidatorResult::new(violations, base.baseline_version, deployment_version)
}

#[cfg(test)]
mod tests {
    use super::*;
    use awd_domain::validator::{Severity, Violation};

    struct Warn;
    impl DeploymentValidator for Warn {
        fn check(&self, _text: &str) -> Vec<Violation> {
            vec![Violation {
                code: "deploy_warn".into(),
                severity: Severity::Warning,
                span: None,
                locale_key: "x".into(),
            }]
        }
        fn version(&self) -> Option<String> {
            Some("dep-1".into())
        }
    }

    struct Block;
    impl DeploymentValidator for Block {
        fn check(&self, _text: &str) -> Vec<Violation> {
            vec![Violation {
                code: "deploy_block".into(),
                severity: Severity::Error,
                span: None,
                locale_key: "x".into(),
            }]
        }
        fn version(&self) -> Option<String> {
            Some("dep-2".into())
        }
    }

    #[test]
    fn no_deployment_validators_equals_baseline() {
        let r = check("hello there", &[]);
        assert!(r.passed);
        assert_eq!(r.deployment_version, None);
        assert_eq!(r.baseline_version, baseline::version());
    }

    #[test]
    fn warning_does_not_block_but_records_version() {
        let w = Warn;
        let r = check("hello there", &[&w]);
        assert!(r.passed);
        assert_eq!(r.violations.len(), 1);
        assert_eq!(r.deployment_version, Some("dep-1".into()));
    }

    #[test]
    fn error_blocks_and_versions_join() {
        let w = Warn;
        let b = Block;
        let r = check("hello there", &[&w, &b]);
        assert!(!r.passed);
        assert_eq!(r.deployment_version, Some("dep-1,dep-2".into()));
    }

    #[test]
    fn baseline_violations_carry_through() {
        let r = check("I guarantee it", &[]);
        assert!(!r.passed);
        assert!(r.violations.iter().any(|v| v.code == "guarantee_claim"));
    }
}
