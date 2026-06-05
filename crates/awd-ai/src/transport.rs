//! Anthropic request building, response parsing, and the load-bearing HTTP
//! error classification — the pure parts of `ai/adapters/anthropic.ex`.
//!
//! The reqwest call itself is deferred to the network phase; everything a
//! worker branches on (the [`AiError`] classification, the request body, usage
//! extraction) is pure and tested here. The HTTP layer will be a thin wrapper:
//! build body → POST → hand `(status, json_body)` to
//! [`classify_response`].

use crate::prompt::Prompt;
use serde_json::{json, Map, Value};

pub const MESSAGES_URL: &str = "https://api.anthropic.com/v1/messages";
pub const ANTHROPIC_VERSION: &str = "2023-06-01";
pub const DEFAULT_MAX_TOKENS: u32 = 1024;

/// Error classes the worker branches on (architecture §4.4). `RateLimited`,
/// `Transient`, and `Timeout` are retryable; `Permanent`, `ContentBlocked`, and
/// `ModelNotAllowed` are not.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AiError {
    #[error("rate limited (429)")]
    RateLimited,
    #[error("transient upstream error")]
    Transient,
    #[error("permanent error (caller/config)")]
    Permanent,
    #[error("content blocked by provider safety stack")]
    ContentBlocked,
    #[error("request timed out")]
    Timeout,
    #[error("model not allowed: {0}")]
    ModelNotAllowed(String),
}

/// Normalized success usage block.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_input_tokens: u64,
    pub cache_creation_input_tokens: u64,
}

/// Normalized success response.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub text: String,
    pub usage: Usage,
    pub stop_reason: Option<String>,
    pub raw: Value,
}

/// Reject any model not in the allowlist BEFORE any network call.
pub fn validate_model(model: &str, allowlist: &[&str]) -> Result<(), AiError> {
    if allowlist.contains(&model) {
        Ok(())
    } else {
        Err(AiError::ModelNotAllowed(model.to_string()))
    }
}

/// Build the JSON request body (`build_body/2` + `render_system_blocks/1` +
/// `maybe_put_metadata/2`).
pub fn build_body(prompt: &Prompt, model: &str) -> Value {
    let system: Vec<Value> = prompt
        .system_blocks
        .iter()
        .map(|b| {
            let mut block = Map::new();
            block.insert("type".into(), json!("text"));
            block.insert("text".into(), json!(b.text));
            if b.cache_control_ephemeral {
                block.insert("cache_control".into(), json!({ "type": "ephemeral" }));
            }
            Value::Object(block)
        })
        .collect();

    let messages: Vec<Value> = prompt
        .messages
        .iter()
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();

    let mut body = Map::new();
    body.insert("model".into(), json!(model));
    body.insert(
        "max_tokens".into(),
        json!(prompt.max_tokens.unwrap_or(DEFAULT_MAX_TOKENS)),
    );
    body.insert("system".into(), Value::Array(system));
    body.insert("messages".into(), Value::Array(messages));

    // metadata.user_id = requestor_actor_id (never raw PII), when present.
    if let Some(actor) = prompt
        .metadata
        .get("requestor_actor_id")
        .and_then(|v| {
            v.as_str()
                .map(str::to_string)
                .or_else(|| Some(v.to_string()))
        })
        .filter(|_| !prompt.metadata.get("requestor_actor_id").unwrap().is_null())
    {
        body.insert("metadata".into(), json!({ "user_id": actor }));
    }

    Value::Object(body)
}

/// Map an HTTP `(status, body)` to a success or a classified error
/// (`do_complete/3`'s case). A content-policy refusal arrives as a 200 with
/// `stop_reason: "refusal"` — surfaced as `Ok` for the worker to handle.
pub fn classify_response(status: u16, body: &Value) -> Result<Response, AiError> {
    match status {
        200 => Ok(normalize_success(body)),
        429 => Err(AiError::RateLimited),
        s if s >= 500 => Err(AiError::Transient),
        400 => Err(classify_400(body)),
        s if (401..=499).contains(&s) => Err(AiError::Permanent),
        // Unexpected non-200 success/redirect: retrying won't help.
        _ => Err(AiError::Permanent),
    }
}

fn classify_400(body: &Value) -> AiError {
    match body
        .get("error")
        .and_then(|e| e.get("type"))
        .and_then(Value::as_str)
    {
        Some("invalid_request_error") => AiError::Permanent,
        _ => AiError::ContentBlocked,
    }
}

fn normalize_success(body: &Value) -> Response {
    Response {
        text: extract_text(body),
        usage: extract_usage(body),
        stop_reason: body
            .get("stop_reason")
            .and_then(Value::as_str)
            .map(str::to_string),
        raw: body.clone(),
    }
}

fn extract_text(body: &Value) -> String {
    body.get("content")
        .and_then(Value::as_array)
        .map(|blocks| {
            blocks
                .iter()
                .filter(|b| b.get("type").and_then(Value::as_str) == Some("text"))
                .filter_map(|b| b.get("text").and_then(Value::as_str))
                .collect::<String>()
        })
        .unwrap_or_default()
}

fn extract_usage(body: &Value) -> Usage {
    let usage = body.get("usage").cloned().unwrap_or(Value::Null);
    let field = |k: &str| usage.get(k).and_then(Value::as_u64).unwrap_or(0);
    Usage {
        input_tokens: field("input_tokens"),
        output_tokens: field("output_tokens"),
        cache_read_input_tokens: field("cache_read_input_tokens"),
        cache_creation_input_tokens: field("cache_creation_input_tokens"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::prompt::{ChatMessage, Prompt, SystemBlock};

    fn prompt() -> Prompt {
        Prompt {
            model: Some("claude-sonnet-4-6".into()),
            max_tokens: None,
            system_blocks: vec![
                SystemBlock {
                    text: "fw".into(),
                    cache_control_ephemeral: true,
                },
                SystemBlock {
                    text: "conv".into(),
                    cache_control_ephemeral: false,
                },
            ],
            messages: vec![ChatMessage {
                role: "user".into(),
                content: "hi".into(),
            }],
            metadata: json!({ "requestor_actor_id": "op-123" }),
        }
    }

    #[test]
    fn model_allowlist_enforced() {
        assert!(validate_model("claude-sonnet-4-6", &["claude-sonnet-4-6"]).is_ok());
        assert_eq!(
            validate_model("gpt-9", &["claude-sonnet-4-6"]),
            Err(AiError::ModelNotAllowed("gpt-9".into()))
        );
    }

    #[test]
    fn body_shape_and_cache_markers() {
        let b = build_body(&prompt(), "claude-sonnet-4-6");
        assert_eq!(b["model"], json!("claude-sonnet-4-6"));
        assert_eq!(b["max_tokens"], json!(DEFAULT_MAX_TOKENS)); // None → default
        let system = b["system"].as_array().unwrap();
        assert_eq!(system[0]["cache_control"], json!({ "type": "ephemeral" }));
        assert!(system[1].get("cache_control").is_none()); // conversation uncached
        assert_eq!(b["metadata"]["user_id"], json!("op-123"));
        assert_eq!(b["messages"][0]["role"], json!("user"));
    }

    #[test]
    fn no_metadata_key_when_absent() {
        let mut p = prompt();
        p.metadata = json!({});
        let b = build_body(&p, "m");
        assert!(b.get("metadata").is_none());
    }

    #[test]
    fn classification_table() {
        assert_eq!(
            classify_response(429, &json!({})),
            Err(AiError::RateLimited)
        );
        assert_eq!(classify_response(503, &json!({})), Err(AiError::Transient));
        assert_eq!(classify_response(500, &json!({})), Err(AiError::Transient));
        assert_eq!(
            classify_response(400, &json!({"error": {"type": "invalid_request_error"}})),
            Err(AiError::Permanent)
        );
        assert_eq!(
            classify_response(400, &json!({"error": {"type": "overloaded_error"}})),
            Err(AiError::ContentBlocked)
        );
        assert_eq!(
            classify_response(400, &json!({})),
            Err(AiError::ContentBlocked)
        );
        for s in [401, 403, 404, 413, 499] {
            assert_eq!(classify_response(s, &json!({})), Err(AiError::Permanent));
        }
    }

    #[test]
    fn success_normalization() {
        let body = json!({
            "content": [
                {"type": "text", "text": "Hello "},
                {"type": "thinking", "text": "ignored"},
                {"type": "text", "text": "there"}
            ],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 10, "output_tokens": 4, "cache_read_input_tokens": 2}
        });
        let r = classify_response(200, &body).unwrap();
        assert_eq!(r.text, "Hello there"); // only text blocks, concatenated
        assert_eq!(r.stop_reason.as_deref(), Some("end_turn"));
        assert_eq!(r.usage.input_tokens, 10);
        assert_eq!(r.usage.output_tokens, 4);
        assert_eq!(r.usage.cache_read_input_tokens, 2);
        assert_eq!(r.usage.cache_creation_input_tokens, 0); // missing → 0
    }

    #[test]
    fn refusal_is_ok_with_stop_reason() {
        let body = json!({"content": [], "stop_reason": "refusal"});
        let r = classify_response(200, &body).unwrap();
        assert_eq!(r.stop_reason.as_deref(), Some("refusal"));
        assert_eq!(r.text, "");
    }
}
