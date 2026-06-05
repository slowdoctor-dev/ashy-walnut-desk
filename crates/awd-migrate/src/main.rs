//! # awd-migrate
//!
//! One-shot data migration from the legacy Ash/Ecto Postgres schema into the
//! new Rust-owned schema: copy in FK order (UUIDs preserved), recompute/verify
//! every audit chain (byte-exact primary, re-anchor + `legacy_hash` fallback),
//! and a permanent `audit verify` subcommand mirroring `mix audit.verify`.
//!
//! Phase 0/2/6. Scaffold only.

fn main() {
    // Pulls in the verified domain canonicalization the verifier will use.
    let _ = awd_domain::audit::EventType::InboxOpened;
    let _ = awd_db::awd_domain::countdown::COUNTDOWN_SECONDS;
    println!("awd-migrate: scaffold — see compiled-scribbling-crown.md for the migration plan");
}
