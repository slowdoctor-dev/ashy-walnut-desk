//! # awd-auth
//!
//! Hand-built replacement for `ash_authentication`, pure parts implemented and
//! tested:
//!
//! - [`roles`] — the role model + capability predicates (`AdminOrOperator`) +
//!   the first-user-admin election (`AssignFirstUserAdmin.choose_role`).
//! - [`jwt`] — HS256 mint/verify with a `jti` session id + expiry.
//! - [`magic_link`] — random token generation + stored-hash verification.
//!
//! **Deferred to a Postgres-equipped env:** the DB token store, the
//! per-request token-presence check (revocation by `jti`), the registration
//! gate, and the boot-time system actor — all need SQLx.

pub mod jwt;
pub mod magic_link;
pub mod roles;

pub use awd_domain;
pub use roles::Role;
