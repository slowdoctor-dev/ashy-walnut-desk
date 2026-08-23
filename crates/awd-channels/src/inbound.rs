//! Canonical inbound-message type produced by channel adapters' `parse_inbound`
//! (the transient parse struct from `interaction/inbound_message.ex`).

use chrono::{DateTime, Utc};

/// The inbound delivery providers (matches the `inbound_deliveries.provider`
/// CHECK + `inbound_message.ex`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Provider {
    Twilio,
    Stub,
    Echo,
}

impl Provider {
    pub const fn as_str(self) -> &'static str {
        match self {
            Provider::Twilio => "twilio",
            Provider::Stub => "stub",
            Provider::Echo => "echo",
        }
    }
}

/// A parsed inbound message, normalized across channels.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InboundMessage {
    pub provider: Provider,
    pub provider_message_id: String,
    pub from: String,
    pub to: String,
    pub body: String,
    pub received_at: DateTime<Utc>,
}
