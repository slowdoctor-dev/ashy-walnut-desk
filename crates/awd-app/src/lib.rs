//! # awd-app
//!
//! The application/orchestration layer — the thing Ash *actions* actually were.
//! The transactional functions (`draft::approve`, `action::execute`, …) compose
//! repos + jobs + audit appends behind one SQLx transaction and need a DB; they
//! are deferred. Implemented and tested here is the **pure authorization core**:
//!
//! - [`policy`] — the generic `authorize`/`authorize_record` primitives (Ash
//!   `policies`) + the per-field `Visibility` primitive (Ash `field_policies`).
//! - [`draft`] — the Draft action/field tables (from `draft.ex`), the typed
//!   exemplar with a `DraftAction` enum + role-aware row redaction.
//! - [`resources`] — the equivalent tables for every other resource (the
//!   four-stage chain, identity axis, knowledge, accounts), ported 1:1.

pub mod draft;
pub mod orchestrate;
pub mod policy;
pub mod resources;

pub use awd_auth;
pub use awd_db;
pub use awd_domain;
pub use awd_safety;
