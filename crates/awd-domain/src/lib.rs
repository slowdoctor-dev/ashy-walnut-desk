//! # awd-domain
//!
//! The pure domain core of ashy-walnut-desk — **no I/O, no async**. This crate
//! is the frozen spec for the product's safety invariants and is the foundation
//! every other crate depends on:
//!
//! - [`audit`] — the tamper-evident hash-chain (canonicalization + SHA-256).
//! - [`state`] — the four-stage record-chain state machines (ADR-016).
//! - [`countdown`] — the 5-second send guard (ADR-013).
//! - [`identifier`] — E.164 normalization + salted identifier/email hashing.
//! - [`validator`] — safety-validator result types + the composite pass rule.
//!
//! Behavior here is ported line-for-line from the original Elixir/Ash modules
//! and must not change without an ADR (and, for the audit chain, a re-anchor).

pub mod audit;
pub mod countdown;
pub mod identifier;
pub mod state;
pub mod validator;
