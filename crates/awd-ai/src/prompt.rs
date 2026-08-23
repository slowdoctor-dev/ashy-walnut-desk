//! Prompt value types — the assembled request the Anthropic adapter serializes.
//! Mirrors `ai/prompt.ex`.

use chrono::{DateTime, Utc};

/// Inbound vs outbound message in the conversation transcript.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Inbound,
    Outbound,
}

/// A conversation message fed to the assembler. (A nil/unknown direction in the
/// Elixir source is treated as `Inbound`; construct it that way here.)
#[derive(Debug, Clone)]
pub struct Message {
    pub direction: Direction,
    pub body: String,
    pub inserted_at: Option<DateTime<Utc>>,
}

/// A system prompt block. `cache_control_ephemeral` forwards the
/// `cache_control: {type: "ephemeral"}` marker (set on framework + persona).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemBlock {
    pub text: String,
    pub cache_control_ephemeral: bool,
}

/// A chat message in the `messages` array.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

/// The assembled prompt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Prompt {
    pub model: Option<String>,
    pub max_tokens: Option<u32>,
    pub system_blocks: Vec<SystemBlock>,
    pub messages: Vec<ChatMessage>,
    pub metadata: serde_json::Value,
}

/// Persona content used to build the persona system block.
#[derive(Debug, Clone, Default)]
pub struct Persona {
    pub system_prompt: Option<String>,
    pub guardrail_notes: Option<String>,
}
