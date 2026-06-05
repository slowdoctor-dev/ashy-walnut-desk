//! # awd-safety
//!
//! The regex validator stack ported from `safety/validators/*`:
//!
//! - [`baseline`] — guarantee/diagnostic/pricing/prohibited/length + honest
//!   framing, plus the Rust-native deterministic `baseline_version`.
//! - [`composite`] — baseline + deployer-supplied [`composite::DeploymentValidator`]s.
//!
//! Both produce an [`awd_domain::validator::ValidatorResult`]; a result passes
//! iff it carries no `Error`-severity violation.

pub mod baseline;
pub mod composite;

pub use awd_domain;
pub use baseline::version as baseline_version;
