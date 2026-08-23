//! Audit hash-chain — faithful port of `interaction/audit_chain.ex` +
//! the payload construction in `interaction/changes/chain_link.ex`.
//!
//! # Invariants (do not change without an ADR + chain re-anchor)
//!
//! Each audit event's hash is:
//!
//! ```text
//! hash = lower_hex( SHA256( prev_hash_hex_or_"" ++ canonical_json ) )
//! ```
//!
//! where `prev_hash` is the *previous* event's hex string (or `""` for the
//! first event in a chain) concatenated to the canonical JSON *string*.
//!
//! `canonical_json` is built from a per-event-type **allowlist** of keys.
//! Every allowed key is always emitted (absent keys become JSON `null`),
//! values are coerced (`DateTime` → ISO-8601, atoms/enums → their string),
//! and the object is serialized **compact** with keys in **byte-lexicographic
//! order**.
//!
//! ## Two quirks reproduced verbatim from the Elixir source
//!
//! 1. **Key ordering.** The Elixir code builds the canonical map in allowlist
//!    order but lets `Jason.encode/1` re-serialize it. Jason emits an Elixir
//!    flat map (≤32 keys — every payload here has ≤11) in **key term order**,
//!    which for binary (string) keys is byte-lexicographic. We therefore sort
//!    keys by their UTF-8 bytes, not by allowlist order. (Validate against a
//!    production `audit_events` dump in Phase 0 — see plan.)
//!
//! 2. **The `||` falsy collapse.** `value = Map.get(payload, key) ||
//!    Map.get(payload, to_string(key))`. At write time the payload is
//!    atom-keyed, so the right side is always `nil`; the net effect is
//!    `value = atom_value || nil`. In Elixir only `nil` and `false` are
//!    falsy, so a `false` boolean (the only one is `validator_passed?`)
//!    collapses to `nil` → canonical `null`. We reproduce this: a `false`
//!    or absent/`null` value canonicalizes to `null`. Integers (incl. `0`),
//!    empty strings, and empty lists are truthy in Elixir and pass through.
//!
//!    NOTE: this means a validator-failed completion records
//!    `"validator_passed?": null` in the *hashed* canonical form (the stored
//!    `payload` jsonb still keeps the real `false` for display). This matches
//!    the Elixir **write** path and thus the stored hashes. Flagged for
//!    Phase-0 cross-check against real data.

use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

/// Audit event types — string forms must match the Elixir `@payload_allowlist`
/// keys and the `event_type` column exactly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventType {
    InboxOpened,
    DraftStarted,
    DraftGenerationRequested,
    DraftGenerationCompleted,
    DraftGenerationFailed,
    DraftSuperseded,
    DraftApproved,
    ActionScheduled,
    ActionExecuted,
    CompensationRegistered,
    CompensationScheduled,
    CompensationExecuted,
}

impl EventType {
    pub const fn as_str(self) -> &'static str {
        match self {
            EventType::InboxOpened => "inbox_opened",
            EventType::DraftStarted => "draft_started",
            EventType::DraftGenerationRequested => "draft_generation_requested",
            EventType::DraftGenerationCompleted => "draft_generation_completed",
            EventType::DraftGenerationFailed => "draft_generation_failed",
            EventType::DraftSuperseded => "draft_superseded",
            EventType::DraftApproved => "draft_approved",
            EventType::ActionScheduled => "action_scheduled",
            EventType::ActionExecuted => "action_executed",
            EventType::CompensationRegistered => "compensation_registered",
            EventType::CompensationScheduled => "compensation_scheduled",
            EventType::CompensationExecuted => "compensation_executed",
        }
    }

    #[allow(clippy::should_implement_trait)] // intentional infallible Option parser
    pub fn from_str(s: &str) -> Option<EventType> {
        Some(match s {
            "inbox_opened" => EventType::InboxOpened,
            "draft_started" => EventType::DraftStarted,
            "draft_generation_requested" => EventType::DraftGenerationRequested,
            "draft_generation_completed" => EventType::DraftGenerationCompleted,
            "draft_generation_failed" => EventType::DraftGenerationFailed,
            "draft_superseded" => EventType::DraftSuperseded,
            "draft_approved" => EventType::DraftApproved,
            "action_scheduled" => EventType::ActionScheduled,
            "action_executed" => EventType::ActionExecuted,
            "compensation_registered" => EventType::CompensationRegistered,
            "compensation_scheduled" => EventType::CompensationScheduled,
            "compensation_executed" => EventType::CompensationExecuted,
            _ => return None,
        })
    }
}

/// A payload value before canonicalization. Mirrors the narrow value domain
/// that actually enters the chain (no floats, no nested maps, no free text).
#[derive(Debug, Clone, PartialEq)]
pub enum PayloadValue {
    Str(String),
    Int(i64),
    Bool(bool),
    /// e.g. `superseded_sibling_draft_ids` — a list of UUID strings.
    StrList(Vec<String>),
    /// Canonicalizes to `DateTime.to_iso8601/1`: `%Y-%m-%dT%H:%M:%S%.6fZ`.
    DateTime(chrono::DateTime<chrono::Utc>),
    Null,
}

impl PayloadValue {
    /// Reproduces `value || nil` then `canonical_value/1`: `false`/`Null`
    /// collapse to JSON `null`; everything else maps directly.
    fn to_canonical(&self) -> serde_json::Value {
        use serde_json::Value;
        match self {
            PayloadValue::Null | PayloadValue::Bool(false) => Value::Null,
            PayloadValue::Bool(true) => Value::Bool(true),
            PayloadValue::Int(i) => Value::Number((*i).into()),
            PayloadValue::Str(s) => Value::String(s.clone()),
            PayloadValue::StrList(items) => {
                Value::Array(items.iter().map(|s| Value::String(s.clone())).collect())
            }
            PayloadValue::DateTime(dt) => Value::String(iso8601_micros(*dt)),
        }
    }
}

/// `DateTime.to_iso8601/1` for a `utc_datetime_usec`: always `Z`, exactly six
/// fractional digits. The only datetime in any payload is `approved_at`.
fn iso8601_micros(dt: chrono::DateTime<chrono::Utc>) -> String {
    dt.format("%Y-%m-%dT%H:%M:%S%.6fZ").to_string()
}

/// A logical audit payload keyed by attribute name (string keys, matching the
/// DB/jsonb form). Use a `BTreeMap` so iteration/unknown-key checks are
/// deterministic; the final canonical key order is enforced separately.
pub type Payload = BTreeMap<String, PayloadValue>;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AuditError {
    #[error("unknown event type for payload canonicalization")]
    UnknownEventType,
    #[error("payload key not allowed for this event type: {0}")]
    InvalidPayloadKey(String),
    #[error("canonical JSON serialization failed")]
    Serialization,
}

/// Per-event-type allowlist of payload keys, in the Elixir-declared order.
/// (Canonical serialization re-sorts by bytes; this order is only for parity
/// and the `draft_approved` special case.)
fn allowlist(event_type: EventType) -> &'static [&'static str] {
    match event_type {
        EventType::InboxOpened => &["inbox_id", "conversation_id", "identity_id"],
        EventType::DraftStarted => &["inbox_id", "draft_id"],
        EventType::DraftGenerationRequested => &[
            "draft_id",
            "inbox_id",
            "persona_id",
            "persona_slug",
            "model",
            "actor_id",
        ],
        EventType::DraftGenerationCompleted => &[
            "draft_id",
            "inbox_id",
            "model",
            "input_tokens",
            "output_tokens",
            "cache_read_tokens",
            "cache_creation_tokens",
            "validator_passed?",
            "violations_count",
            "baseline_version",
            "deployment_version",
        ],
        EventType::DraftGenerationFailed => &[
            "draft_id",
            "inbox_id",
            "model",
            "error_class",
            "error_detail_redacted",
        ],
        EventType::DraftSuperseded => &["draft_id", "inbox_id"],
        // draft_approved is special-cased in `allowed_keys_for`.
        EventType::DraftApproved => &[
            "draft_id",
            "approved_at",
            "approved_by_id",
            "superseded_sibling_draft_ids",
        ],
        EventType::ActionScheduled => &["action_id", "draft_id", "channel_id"],
        EventType::ActionExecuted => &["action_id", "draft_id", "channel_id", "outcome"],
        EventType::CompensationRegistered => &["compensation_id", "action_id"],
        EventType::CompensationScheduled => &["compensation_id", "action_id"],
        EventType::CompensationExecuted => &["compensation_id", "action_id", "outcome"],
    }
}

/// Mirrors `allowed_keys_for/2`: `draft_approved` drops
/// `superseded_sibling_draft_ids` from the allowlist when the payload doesn't
/// carry it (back-compat with pre-supersede events).
fn allowed_keys_for(event_type: EventType, payload: &Payload) -> &'static [&'static str] {
    match event_type {
        EventType::DraftApproved => {
            if payload.contains_key("superseded_sibling_draft_ids") {
                &[
                    "draft_id",
                    "approved_at",
                    "approved_by_id",
                    "superseded_sibling_draft_ids",
                ]
            } else {
                &["draft_id", "approved_at", "approved_by_id"]
            }
        }
        other => allowlist(other),
    }
}

/// Build the canonical (key, value) pairs for an event payload: allowlist
/// filtered, every allowed key present (absent → `Null`), values coerced.
/// Rejects payloads carrying keys outside the allowlist.
pub fn canonicalize_payload(
    event_type: EventType,
    payload: &Payload,
) -> Result<Vec<(String, serde_json::Value)>, AuditError> {
    let allowed = allowed_keys_for(event_type, payload);

    // reject_unknown_keys/2
    for key in payload.keys() {
        if !allowed.contains(&key.as_str()) {
            return Err(AuditError::InvalidPayloadKey(key.clone()));
        }
    }

    let pairs = allowed
        .iter()
        .map(|&key| {
            let value = payload
                .get(key)
                .map(PayloadValue::to_canonical)
                .unwrap_or(serde_json::Value::Null);
            (key.to_string(), value)
        })
        .collect();

    Ok(pairs)
}

/// Serialize canonical pairs to the exact byte string `Jason.encode/1` would
/// produce for the equivalent flat map: compact, keys sorted by UTF-8 bytes.
pub fn to_canonical_json(pairs: &[(String, serde_json::Value)]) -> Result<String, AuditError> {
    let mut sorted: Vec<&(String, serde_json::Value)> = pairs.iter().collect();
    sorted.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));

    let mut out = String::from("{");
    for (i, (key, value)) in sorted.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let key_json = serde_json::to_string(key).map_err(|_| AuditError::Serialization)?;
        let val_json = serde_json::to_string(value).map_err(|_| AuditError::Serialization)?;
        out.push_str(&key_json);
        out.push(':');
        out.push_str(&val_json);
    }
    out.push('}');
    Ok(out)
}

/// `compute_hash/2`: `lower_hex( SHA256( prev_hash_or_"" ++ canonical_json ) )`.
pub fn compute_hash(prev_hash: Option<&str>, canonical_json: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(prev_hash.unwrap_or("").as_bytes());
    hasher.update(canonical_json.as_bytes());
    hex::encode(hasher.finalize())
}

/// Convenience: canonicalize + hash in one step.
pub fn recompute_hash(
    prev_hash: Option<&str>,
    event_type: EventType,
    payload: &Payload,
) -> Result<String, AuditError> {
    let pairs = canonicalize_payload(event_type, payload)?;
    let json = to_canonical_json(&pairs)?;
    Ok(compute_hash(prev_hash, &json))
}

/// One event as seen by the verifier (the db/migrate layer owns row types and
/// adapts them to this view).
pub struct ChainEvent<'a> {
    pub event_type: EventType,
    pub payload: &'a Payload,
    pub stored_hash: &'a str,
}

/// Result of walking a single chain (one `chain_topic`), ordered
/// `(inserted_at ASC, id ASC)`. Mirrors `AuditChain.walk/1` (halts on first
/// mismatch).
#[derive(Debug, PartialEq, Eq)]
pub enum WalkResult {
    Ok {
        length: usize,
    },
    /// Zero-based index of the first event whose recomputed hash != stored.
    BrokenAt(usize),
    Error(AuditError),
}

/// Recompute the chain in order and confirm every stored hash. The previous
/// hash fed into each step is the prior event's **stored** hash (matching the
/// Elixir walker, which chains on `event.hash`).
pub fn verify_chain(events: &[ChainEvent<'_>]) -> WalkResult {
    let mut prev: Option<&str> = None;
    for (idx, ev) in events.iter().enumerate() {
        match recompute_hash(prev, ev.event_type, ev.payload) {
            Ok(computed) => {
                if computed != ev.stored_hash {
                    return WalkResult::BrokenAt(idx);
                }
                prev = Some(ev.stored_hash);
            }
            Err(e) => return WalkResult::Error(e),
        }
    }
    WalkResult::Ok {
        length: events.len(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(pairs: &[(&str, PayloadValue)]) -> Payload {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect()
    }

    #[test]
    fn empty_prev_hash_matches_no_prefix() {
        let json = r#"{"a":1}"#;
        assert_eq!(compute_hash(None, json), compute_hash(Some(""), json));
    }

    #[test]
    fn hash_is_lowercase_hex_sha256() {
        // Known vector: SHA256("{}") with empty prev.
        let h = compute_hash(None, "{}");
        assert_eq!(h.len(), 64);
        assert!(h
            .chars()
            .all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
        // sha256("{}") = 44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a
        assert_eq!(
            h,
            "44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
        );
    }

    #[test]
    fn prev_hash_is_prefix_concatenation() {
        // sha256("PREV" ++ "{}")
        let h = compute_hash(Some("PREV"), "{}");
        let expected = {
            let mut hasher = Sha256::new();
            hasher.update(b"PREV{}");
            hex::encode(hasher.finalize())
        };
        assert_eq!(h, expected);
    }

    #[test]
    fn keys_serialize_in_byte_lexicographic_order() {
        let payload = p(&[
            ("inbox_id", PayloadValue::Str("ib".into())),
            ("conversation_id", PayloadValue::Str("cv".into())),
            ("identity_id", PayloadValue::Str("id".into())),
        ]);
        let pairs = canonicalize_payload(EventType::InboxOpened, &payload).unwrap();
        let json = to_canonical_json(&pairs).unwrap();
        // sorted: conversation_id < identity_id < inbox_id
        assert_eq!(
            json,
            r#"{"conversation_id":"cv","identity_id":"id","inbox_id":"ib"}"#
        );
    }

    #[test]
    fn absent_allowed_key_becomes_null() {
        // draft_generation_requested with model + persona_slug omitted.
        let payload = p(&[
            ("draft_id", PayloadValue::Str("d".into())),
            ("inbox_id", PayloadValue::Str("i".into())),
            ("persona_id", PayloadValue::Str("p".into())),
            ("actor_id", PayloadValue::Str("a".into())),
        ]);
        let pairs = canonicalize_payload(EventType::DraftGenerationRequested, &payload).unwrap();
        let map: std::collections::HashMap<_, _> = pairs.iter().cloned().collect();
        assert_eq!(map["model"], serde_json::Value::Null);
        assert_eq!(map["persona_slug"], serde_json::Value::Null);
    }

    #[test]
    fn validator_passed_false_collapses_to_null() {
        // The documented `||` quirk: false -> null in the hashed form.
        let payload = p(&[("validator_passed?", PayloadValue::Bool(false))]);
        let v = payload["validator_passed?"].to_canonical();
        assert_eq!(v, serde_json::Value::Null);

        let payload_true = p(&[("validator_passed?", PayloadValue::Bool(true))]);
        assert_eq!(
            payload_true["validator_passed?"].to_canonical(),
            serde_json::Value::Bool(true)
        );
    }

    #[test]
    fn zero_int_and_empty_list_are_truthy_passthrough() {
        assert_eq!(
            PayloadValue::Int(0).to_canonical(),
            serde_json::Value::Number(0.into())
        );
        assert_eq!(
            PayloadValue::StrList(vec![]).to_canonical(),
            serde_json::Value::Array(vec![])
        );
    }

    #[test]
    fn unknown_key_is_rejected() {
        let payload = p(&[
            ("draft_id", PayloadValue::Str("d".into())),
            ("inbox_id", PayloadValue::Str("i".into())),
            ("bogus", PayloadValue::Int(1)),
        ]);
        assert_eq!(
            canonicalize_payload(EventType::DraftStarted, &payload),
            Err(AuditError::InvalidPayloadKey("bogus".into()))
        );
    }

    #[test]
    fn draft_approved_special_case_three_vs_four_keys() {
        let without = p(&[
            ("draft_id", PayloadValue::Str("d".into())),
            ("approved_by_id", PayloadValue::Str("u".into())),
        ]);
        let pairs = canonicalize_payload(EventType::DraftApproved, &without).unwrap();
        assert!(!pairs
            .iter()
            .any(|(k, _)| k == "superseded_sibling_draft_ids"));

        let with = p(&[
            ("draft_id", PayloadValue::Str("d".into())),
            ("approved_by_id", PayloadValue::Str("u".into())),
            (
                "superseded_sibling_draft_ids",
                PayloadValue::StrList(vec!["x".into()]),
            ),
        ]);
        let pairs = canonicalize_payload(EventType::DraftApproved, &with).unwrap();
        assert!(pairs
            .iter()
            .any(|(k, _)| k == "superseded_sibling_draft_ids"));
    }

    #[test]
    fn datetime_canonicalizes_to_iso8601_micros() {
        let dt = chrono::DateTime::parse_from_rfc3339("2026-06-05T12:34:56.123456Z")
            .unwrap()
            .with_timezone(&chrono::Utc);
        assert_eq!(
            PayloadValue::DateTime(dt).to_canonical(),
            serde_json::Value::String("2026-06-05T12:34:56.123456Z".into())
        );
    }

    #[test]
    fn verify_chain_detects_break() {
        let pa = p(&[
            ("inbox_id", PayloadValue::Str("i".into())),
            ("draft_id", PayloadValue::Str("d".into())),
        ]);
        let h0 = recompute_hash(None, EventType::DraftStarted, &pa).unwrap();
        let pb = p(&[
            ("draft_id", PayloadValue::Str("d".into())),
            ("inbox_id", PayloadValue::Str("i".into())),
        ]);
        let h1 = recompute_hash(Some(&h0), EventType::DraftSuperseded, &pb).unwrap();

        let good = vec![
            ChainEvent {
                event_type: EventType::DraftStarted,
                payload: &pa,
                stored_hash: &h0,
            },
            ChainEvent {
                event_type: EventType::DraftSuperseded,
                payload: &pb,
                stored_hash: &h1,
            },
        ];
        assert_eq!(verify_chain(&good), WalkResult::Ok { length: 2 });

        let tampered = vec![
            ChainEvent {
                event_type: EventType::DraftStarted,
                payload: &pa,
                stored_hash: &h0,
            },
            ChainEvent {
                event_type: EventType::DraftSuperseded,
                payload: &pb,
                stored_hash: "deadbeef",
            },
        ];
        assert_eq!(verify_chain(&tampered), WalkResult::BrokenAt(1));
    }
}
