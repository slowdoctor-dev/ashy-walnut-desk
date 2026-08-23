//! Twilio SMS adapter — the pure parts of `interaction/adapters/twilio.ex`
//! (+ the signature plug). Outbound HTTP POST is deferred to the network phase;
//! signature verification, inbound parsing, and response classification are
//! pure and tested.

use std::collections::BTreeMap;

use base64::Engine;
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use sha1::Sha1;
use subtle::ConstantTimeEq;

use crate::inbound::{InboundMessage, Provider};

type HmacSha1 = Hmac<Sha1>;

pub const CHANNEL_SLUG: &str = "twilio-sms";

/// Twilio error codes that are permanent (no retry): unsubscribed recipient,
/// region disabled, invalid number, message-blocked filtering.
pub const PERMANENT_TWILIO_CODES: &[i64] = &[21_610, 21_408, 21_211, 30_007];

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum SignatureError {
    #[error("invalid Twilio signature")]
    Invalid,
}

/// Verify `X-Twilio-Signature`: `base64(HMAC-SHA1(secret, url ++ sorted_params))`
/// compared constant-time to the header. `params` are the POST form fields;
/// they are sorted by key and concatenated as `keyvalue` (no separators) — the
/// Twilio canonical string. Empty secret/signature never verify.
pub fn verify_inbound_signature(
    full_url: &str,
    params: &BTreeMap<String, String>,
    signature: &str,
    secret: &str,
) -> Result<(), SignatureError> {
    if secret.is_empty() {
        return Err(SignatureError::Invalid);
    }

    // BTreeMap iterates in sorted-by-key (byte/lexicographic) order, matching
    // Elixir's `Enum.sort_by(fn {k, _} -> k end)`.
    let mut message = String::from(full_url);
    for (k, v) in params {
        message.push_str(k);
        message.push_str(v);
    }

    let mut mac = HmacSha1::new_from_slice(secret.as_bytes()).expect("HMAC accepts any key length");
    mac.update(message.as_bytes());
    let expected = base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes());

    // Constant-time compare (Plug.Crypto.secure_compare). Length check first.
    if expected.len() == signature.len() && expected.as_bytes().ct_eq(signature.as_bytes()).into() {
        Ok(())
    } else {
        Err(SignatureError::Invalid)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ParseError {
    #[error("missing required Twilio fields (MessageSid/From/To/Body)")]
    MissingRequiredFields,
}

/// Lift a Twilio inbound form payload into the canonical [`InboundMessage`].
/// Requires `MessageSid`, `From`, `To`, `Body`. `received_at` is supplied by the
/// caller (the Elixir source ignores `DateSent` and stamps now).
pub fn parse_inbound(
    form: &BTreeMap<String, String>,
    received_at: DateTime<Utc>,
) -> Result<InboundMessage, ParseError> {
    let get = |k: &str| form.get(k).filter(|v| !v.is_empty());
    match (get("MessageSid"), get("From"), get("To"), form.get("Body")) {
        (Some(sid), Some(from), Some(to), Some(body)) => Ok(InboundMessage {
            provider: Provider::Twilio,
            provider_message_id: sid.clone(),
            from: from.clone(),
            to: to.clone(),
            body: body.clone(),
            received_at,
        }),
        _ => Err(ParseError::MissingRequiredFields),
    }
}

/// Outbound send classification (architecture §5.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum SendError {
    #[error("transient Twilio error (retry)")]
    Transient,
    #[error("permanent Twilio error (no retry)")]
    Permanent,
}

/// Normalized success payload from a 2xx Twilio response body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendOutcome {
    pub provider_message_id: Option<String>,
    pub status: String,
    pub to: Option<String>,
}

/// Map `(status, body)` to outcome/error. 2xx → ok; 429 & 5xx → transient;
/// any 4xx → permanent (known codes included).
pub fn classify_send(status: u16, body: &serde_json::Value) -> Result<SendOutcome, SendError> {
    match status {
        200..=299 => Ok(normalize_success(body)),
        429 => Err(SendError::Transient),
        400..=499 => Err(SendError::Permanent),
        s if s >= 500 => Err(SendError::Transient),
        _ => Err(SendError::Transient),
    }
}

fn normalize_success(body: &serde_json::Value) -> SendOutcome {
    SendOutcome {
        provider_message_id: body.get("sid").and_then(|v| v.as_str()).map(str::to_string),
        status: body
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("queued")
            .to_string(),
        to: body.get("to").and_then(|v| v.as_str()).map(str::to_string),
    }
}

/// Is `code` a permanent Twilio failure code?
pub fn is_permanent_code(code: i64) -> bool {
    PERMANENT_TWILIO_CODES.contains(&code)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn params(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn sign(url: &str, p: &BTreeMap<String, String>, secret: &str) -> String {
        let mut msg = String::from(url);
        for (k, v) in p {
            msg.push_str(k);
            msg.push_str(v);
        }
        let mut mac = HmacSha1::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(msg.as_bytes());
        base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes())
    }

    #[test]
    fn valid_signature_accepted() {
        let url = "https://desk.example.com/webhook/twilio";
        let p = params(&[
            ("From", "+15551112222"),
            ("Body", "hi"),
            ("To", "+15553334444"),
        ]);
        let secret = "test_auth_token";
        let sig = sign(url, &p, secret);
        assert!(verify_inbound_signature(url, &p, &sig, secret).is_ok());
    }

    #[test]
    fn tampered_params_or_secret_rejected() {
        let url = "https://desk.example.com/webhook/twilio";
        let p = params(&[("From", "+1"), ("Body", "hi")]);
        let secret = "s";
        let sig = sign(url, &p, secret);

        let mut tampered = p.clone();
        tampered.insert("Body".into(), "HI".into());
        assert_eq!(
            verify_inbound_signature(url, &tampered, &sig, secret),
            Err(SignatureError::Invalid)
        );
        assert_eq!(
            verify_inbound_signature(url, &p, &sig, "wrong"),
            Err(SignatureError::Invalid)
        );
        assert_eq!(
            verify_inbound_signature(url, &p, "", secret),
            Err(SignatureError::Invalid)
        );
        assert_eq!(
            verify_inbound_signature(url, &p, &sig, ""),
            Err(SignatureError::Invalid)
        );
    }

    #[test]
    fn signature_known_vector() {
        // Twilio's documented example: url + sorted params, HMAC-SHA1, base64.
        let url = "https://mycompany.com/myapp.php?foo=1&bar=2";
        let p = params(&[
            ("Digits", "1234"),
            ("To", "+18005551212"),
            ("From", "+14158675309"),
            ("Caller", "+14158675309"),
        ]);
        let secret = "12345";
        let sig = sign(url, &p, secret);
        assert!(verify_inbound_signature(url, &p, &sig, secret).is_ok());
    }

    #[test]
    fn parse_inbound_requires_all_fields() {
        let now = Utc.with_ymd_and_hms(2026, 6, 5, 0, 0, 0).unwrap();
        let full = params(&[
            ("MessageSid", "SM123"),
            ("From", "+1"),
            ("To", "+2"),
            ("Body", "hello"),
        ]);
        let msg = parse_inbound(&full, now).unwrap();
        assert_eq!(msg.provider, Provider::Twilio);
        assert_eq!(msg.provider_message_id, "SM123");
        assert_eq!(msg.body, "hello");

        let missing = params(&[("MessageSid", "SM123"), ("From", "+1")]);
        assert_eq!(
            parse_inbound(&missing, now),
            Err(ParseError::MissingRequiredFields)
        );
    }

    #[test]
    fn send_classification() {
        assert!(classify_send(
            201,
            &serde_json::json!({"sid": "SM1", "status": "queued", "to": "+1"})
        )
        .is_ok());
        assert_eq!(
            classify_send(429, &serde_json::json!({})),
            Err(SendError::Transient)
        );
        assert_eq!(
            classify_send(503, &serde_json::json!({})),
            Err(SendError::Transient)
        );
        assert_eq!(
            classify_send(400, &serde_json::json!({"code": 21610})),
            Err(SendError::Permanent)
        );
        assert_eq!(
            classify_send(404, &serde_json::json!({})),
            Err(SendError::Permanent)
        );
        assert!(is_permanent_code(21610));
        assert!(!is_permanent_code(12345));
    }

    #[test]
    fn success_normalization_defaults_status_queued() {
        let out = classify_send(200, &serde_json::json!({"sid": "SM9"})).unwrap();
        assert_eq!(out.provider_message_id.as_deref(), Some("SM9"));
        assert_eq!(out.status, "queued");
    }
}
