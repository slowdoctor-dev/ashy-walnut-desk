//! Prompt assembler — faithful port of `ai/prompt_assembler.ex`.
//!
//! Builds three system blocks (framework + persona, both ephemeral-cached;
//! conversation, uncached), trims the transcript to a token budget (newest
//! kept, oldest dropped with a sentinel), and selects the user message.

use crate::prompt::{ChatMessage, Direction, Message, Persona, Prompt, SystemBlock};

const FRAMEWORK_HEADER: &str = "[Framework Rules]";
const PERSONA_HEADER: &str = "[Persona Instructions]";
const CONVERSATION_HEADER: &str = "[Conversation Context]";
const PERSONA_MAX_CHARS: usize = 12_000;
const CONVERSATION_TOKEN_CEILING: usize = 4_000;
const HISTORY_LIMIT: usize = 20;
const TRUNCATED_SENTINEL: &str = "[earlier history truncated]";

/// The framework text (already trimmed, matching `String.trim(@framework_text)`).
const FRAMEWORK_TEXT: &str = "You are assisting a front-desk operator by drafting a message.\n\
You do not send messages and must assume a human reviews all output.\n\
Avoid unsupported domain assertions, guarantees, or professional claims.\n\
Keep drafts concise, factual, and safe for operator review.";

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AssembleError {
    #[error("persona system block exceeds {PERSONA_MAX_CHARS} chars")]
    PersonaBlockTooLarge,
}

/// Inputs to [`build`].
pub struct BuildInput {
    pub persona: Persona,
    pub messages: Vec<Message>,
    pub model: Option<String>,
    pub max_tokens: Option<u32>,
    pub metadata: serde_json::Value,
    /// Overrides the auto-selected latest-inbound body when set.
    pub user_message: Option<String>,
}

pub fn build(input: BuildInput) -> Result<Prompt, AssembleError> {
    let persona_text = build_persona_text(&input.persona)?;

    // last `HISTORY_LIMIT` messages, in chronological order.
    let start = input.messages.len().saturating_sub(HISTORY_LIMIT);
    let lines: Vec<String> = input.messages[start..]
        .iter()
        .map(render_transcript_line)
        .collect();
    let conversation_text = trim_conversation(&lines);

    let user_message = input
        .user_message
        .clone()
        .unwrap_or_else(|| latest_inbound_body(&input.messages));

    Ok(Prompt {
        model: input.model,
        max_tokens: input.max_tokens,
        system_blocks: vec![
            SystemBlock {
                text: framework_text(),
                cache_control_ephemeral: true,
            },
            SystemBlock {
                text: persona_text,
                cache_control_ephemeral: true,
            },
            SystemBlock {
                text: conversation_text,
                cache_control_ephemeral: false,
            },
        ],
        messages: vec![ChatMessage {
            role: "user".into(),
            content: user_message,
        }],
        metadata: input.metadata,
    })
}

fn framework_text() -> String {
    format!("{FRAMEWORK_HEADER}\n\n{FRAMEWORK_TEXT}")
}

fn build_persona_text(persona: &Persona) -> Result<String, AssembleError> {
    let system_prompt = persona.system_prompt.as_deref().unwrap_or("").trim();
    let guardrail_block = match persona.guardrail_notes.as_deref() {
        Some(notes) if !notes.trim().is_empty() => {
            Some(format!("Guardrail notes:\n{}", notes.trim()))
        }
        _ => None,
    };

    let mut parts: Vec<String> = vec![PERSONA_HEADER.to_string(), system_prompt.to_string()];
    if let Some(g) = guardrail_block {
        parts.push(g);
    }
    let text = parts.join("\n\n");

    if text.chars().count() > PERSONA_MAX_CHARS {
        Err(AssembleError::PersonaBlockTooLarge)
    } else {
        Ok(text)
    }
}

fn trim_conversation(lines: &[String]) -> String {
    let kept = keep_within_budget(lines);
    let body = kept.join("\n");
    if body.is_empty() {
        CONVERSATION_HEADER.to_string()
    } else {
        format!("{CONVERSATION_HEADER}\n\n{body}")
    }
}

/// Keep newest lines that fit the token ceiling; if any dropped, prepend the
/// truncation sentinel. Result order matches the Elixir source (newest-first).
fn keep_within_budget(lines: &[String]) -> Vec<String> {
    let mut acc: Vec<String> = Vec::new(); // built chronological (prepend oldest-seen)
    let mut dropped = false;

    for line in lines.iter().rev() {
        let mut candidate = acc.clone();
        candidate.insert(0, line.clone());
        if estimate_tokens(&candidate.join("\n")) <= CONVERSATION_TOKEN_CEILING {
            acc.insert(0, line.clone());
        } else {
            dropped = true;
            break;
        }
    }

    let mut kept: Vec<String> = acc.into_iter().rev().collect(); // newest-first
    if dropped && !kept.is_empty() {
        kept.insert(0, TRUNCATED_SENTINEL.to_string());
    }
    kept
}

fn estimate_tokens(text: &str) -> usize {
    (text.chars().count() / 4).max(1)
}

fn render_transcript_line(message: &Message) -> String {
    let direction = match message.direction {
        Direction::Outbound => "Outbound",
        Direction::Inbound => "Inbound",
    };
    let timestamp = match message.inserted_at {
        Some(dt) => dt.format("%Y-%m-%d %H:%M").to_string(),
        None => "unknown".to_string(),
    };
    format!("{direction} ({timestamp}): {}", message.body)
}

fn latest_inbound_body(messages: &[Message]) -> String {
    messages
        .iter()
        .rev()
        .find(|m| m.direction == Direction::Inbound)
        .map(|m| m.body.clone())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn msg(dir: Direction, body: &str) -> Message {
        Message {
            direction: dir,
            body: body.into(),
            inserted_at: Some(chrono::Utc.with_ymd_and_hms(2026, 6, 5, 9, 30, 0).unwrap()),
        }
    }

    fn input(persona: Persona, messages: Vec<Message>) -> BuildInput {
        BuildInput {
            persona,
            messages,
            model: Some("claude-sonnet-4-6".into()),
            max_tokens: Some(512),
            metadata: serde_json::json!({}),
            user_message: None,
        }
    }

    #[test]
    fn three_blocks_with_cache_flags() {
        let p = build(input(
            Persona {
                system_prompt: Some("Be kind.".into()),
                guardrail_notes: None,
            },
            vec![msg(Direction::Inbound, "Hi, are you open?")],
        ))
        .unwrap();

        assert_eq!(p.system_blocks.len(), 3);
        assert!(p.system_blocks[0].cache_control_ephemeral); // framework
        assert!(p.system_blocks[1].cache_control_ephemeral); // persona
        assert!(!p.system_blocks[2].cache_control_ephemeral); // conversation
        assert!(p.system_blocks[0].text.starts_with("[Framework Rules]"));
        assert!(p.system_blocks[1]
            .text
            .starts_with("[Persona Instructions]"));
        assert!(p.system_blocks[2]
            .text
            .starts_with("[Conversation Context]"));
    }

    #[test]
    fn user_message_is_latest_inbound() {
        let p = build(input(
            Persona::default(),
            vec![
                msg(Direction::Inbound, "first"),
                msg(Direction::Outbound, "reply"),
                msg(Direction::Inbound, "latest question"),
            ],
        ))
        .unwrap();
        assert_eq!(p.messages[0].content, "latest question");
        assert_eq!(p.messages[0].role, "user");
    }

    #[test]
    fn user_message_override_wins() {
        let mut i = input(Persona::default(), vec![msg(Direction::Inbound, "x")]);
        i.user_message = Some("explicit".into());
        let p = build(i).unwrap();
        assert_eq!(p.messages[0].content, "explicit");
    }

    #[test]
    fn guardrail_notes_appended_when_present() {
        let p = build(input(
            Persona {
                system_prompt: Some("Tone: warm.".into()),
                guardrail_notes: Some("  Never quote prices.  ".into()),
            },
            vec![],
        ))
        .unwrap();
        let persona = &p.system_blocks[1].text;
        assert!(persona.contains("Tone: warm."));
        assert!(persona.contains("Guardrail notes:\nNever quote prices."));
    }

    #[test]
    fn empty_conversation_is_just_the_header() {
        let p = build(input(Persona::default(), vec![])).unwrap();
        assert_eq!(p.system_blocks[2].text, "[Conversation Context]");
    }

    #[test]
    fn persona_too_large_errors() {
        let huge = "x".repeat(PERSONA_MAX_CHARS + 1);
        let err = build(input(
            Persona {
                system_prompt: Some(huge),
                guardrail_notes: None,
            },
            vec![],
        ))
        .unwrap_err();
        assert_eq!(err, AssembleError::PersonaBlockTooLarge);
    }

    #[test]
    fn history_capped_at_twenty() {
        let messages: Vec<Message> = (0..30)
            .map(|i| msg(Direction::Inbound, &format!("m{i}")))
            .collect();
        let p = build(input(Persona::default(), messages)).unwrap();
        // newest message body m29 present; oldest m0..m9 excluded by the cap.
        assert!(p.system_blocks[2].text.contains("m29"));
        assert!(!p.system_blocks[2].text.contains("m0)"));
    }

    #[test]
    fn budget_trim_prepends_sentinel_and_keeps_newest() {
        // Each line ~1000 chars → ~250 tokens; 4000 ceiling fits ~16. With 20
        // long lines, the oldest are dropped and the sentinel is prepended.
        let long = "z".repeat(1000);
        // Marker `line{i}#` is collision-free (e.g. "line10#" does not contain
        // "line0#"), unlike a bare "{i}:" prefix.
        let messages: Vec<Message> = (0..20)
            .map(|i| msg(Direction::Inbound, &format!("line{i}#{long}")))
            .collect();
        let p = build(input(Persona::default(), messages)).unwrap();
        let conv = &p.system_blocks[2].text;
        assert!(conv.contains(TRUNCATED_SENTINEL));
        assert!(conv.contains("line19#")); // newest kept
        assert!(!conv.contains("line0#")); // oldest dropped
    }
}
