//! # awd-db
//!
//! Persistence for ashy-walnut-desk. This crate currently implements the
//! **pure, database-independent** half of the persistence layer (fully
//! unit-tested):
//!
//! - [`versioning`] — the `ash_paper_trail` replacement: changes-only diff +
//!   sensitive-attribute redaction for `<table>_versions` rows.
//! - [`locks`] — the three `FOR UPDATE` lock statements (`locks.ex`), pinned as
//!   constants shared by the execution layer and tests.
//!
//! The new schema lives in `migrations/*.sql` (run with `sqlx migrate`).
//!
//! **Deferred to a Postgres-equipped environment** (no DB available where this
//! was scaffolded): the SQLx pool/connection, the `sqlx::migrate!` migrator,
//! `FromRow` row structs, the repository functions that execute the queries in
//! [`locks`], the `versioned_write` transaction helper, and integration tests.
//! See the plan (`compiled-scribbling-crown.md`, Phase 2).

pub mod locks;
pub mod versioning;

pub use awd_domain;
