//! # awd-app
//!
//! The application/orchestration layer — the thing Ash *actions* actually were.
//! The transactional functions (`draft::approve`, `action::execute`, …) compose
//! repos + jobs + audit appends behind one SQLx transaction and need a DB; they
//! are deferred. Implemented and tested here is the **pure authorization core**:
//!
//! - [`policy`] — the generic `authorize` primitive (Ash `policies`) + the
//!   per-field `Visibility` primitive (Ash `field_policies`).
//! - [`draft`] — the concrete Draft action/field tables (from `draft.ex`) +
//!   role-aware row redaction. Other resources follow the same one-table shape.

pub mod draft;
pub mod policy;

pub use awd_auth;
pub use awd_db;
pub use awd_domain;
pub use awd_safety;
