//! # awd-ai
//!
//! The Anthropic integration, pure parts implemented and tested:
//!
//! - [`prompt`] — the assembled-prompt value types.
//! - [`assembler`] — `prompt_assembler.ex`: framework/persona/conversation
//!   blocks, token-budget trimming, transcript rendering, user-message select.
//! - [`transport`] — request body building, the load-bearing HTTP error
//!   classification, model allowlist, and success/usage normalization.
//!
//! **Deferred to the network phase:** the reqwest call (the thin wrapper that
//! POSTs [`transport::build_body`] and hands `(status, body)` to
//! [`transport::classify_response`]) and a fixture adapter.

pub mod assembler;
pub mod prompt;
pub mod transport;

pub use awd_domain;
