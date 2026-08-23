//! # awd-web
//!
//! The HTTP/UI surface: Axum server + Tower middleware (per-scope rate limiting,
//! CSP/security headers, Twilio signature verification), the magic-link auth and
//! Twilio webhook controllers, and the Dioxus fullstack pages (Inbox, Identity
//! timeline, Persona, Audit-chain viewer, Welcome) with a server-authoritative
//! countdown. UI logic stays thin — all real logic lives in `awd-app`.
//!
//! Phase 5. Scaffold only.

pub use awd_app;
pub use awd_domain;
