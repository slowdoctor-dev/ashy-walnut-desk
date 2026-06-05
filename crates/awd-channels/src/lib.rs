//! # awd-channels
//!
//! Channel adapters, pure parts implemented and tested:
//!
//! - [`inbound`] — the canonical [`inbound::InboundMessage`] + provider enum.
//! - [`twilio`] — `X-Twilio-Signature` HMAC-SHA1 verification (constant-time),
//!   inbound form parsing, and the outbound send classification table
//!   (transient vs permanent, incl. the permanent Twilio code set).
//!
//! **Deferred to the network phase:** the reqwest outbound POST (HTTP Basic
//! auth + `Idempotency-Key` header) and the echo/stub adapters.

pub mod inbound;
pub mod twilio;

pub use awd_domain;
