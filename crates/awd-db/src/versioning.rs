//! Hand-written `ash_paper_trail` replacement (the pure half).
//!
//! ash_paper_trail config on every versioned resource:
//! `change_tracking_mode(:changes_only)`, `store_action_name?(true)`,
//! `sensitive_attributes(:redact)`. This module computes the `changes` jsonb
//! that the (later) SQLx `versioned_write` helper inserts into a
//! `<table>_versions` row, inside the same transaction as the business write.
//!
//! Rules ported:
//! - **changes_only** — only attributes whose value actually changed are
//!   recorded. On create (`before = None`) every attribute is a change.
//! - **redact** — a sensitive attribute's value is replaced with
//!   [`REDACTED`] (the value never reaches the version log), but the *key* is
//!   still recorded when it changed.

use serde_json::{Map, Value};

/// Marker stored in place of a sensitive attribute's value.
pub const REDACTED: &str = "[redacted]";

/// A versioned resource: its table name and the attributes marked
/// `sensitive? true` (redacted in the version log). Populated from the Elixir
/// resources; extend as resources are ported.
#[derive(Debug, Clone, Copy)]
pub struct Versioned {
    pub table: &'static str,
    pub sensitive: &'static [&'static str],
}

impl Versioned {
    pub const fn versions_table(&self) -> &'static str {
        self.table
    }
}

/// The 11 versioned resources and their sensitive attributes (from the Elixir
/// `sensitive? true` markers). The `*_versions` table name is `<table>_versions`.
pub const VERSIONED: &[Versioned] = &[
    Versioned {
        table: "users",
        sensitive: &["email", "email_hash"],
    },
    Versioned {
        table: "identities",
        sensitive: &[
            "display_name",
            "primary_identifier",
            "primary_identifier_hash",
            "notes_summary",
        ],
    },
    Versioned {
        table: "events",
        sensitive: &["summary", "body"],
    },
    Versioned {
        table: "appointments",
        sensitive: &["summary"],
    },
    Versioned {
        table: "notes",
        sensitive: &["body"],
    },
    Versioned {
        table: "channels",
        sensitive: &[],
    },
    Versioned {
        table: "conversations",
        sensitive: &["subject"],
    },
    Versioned {
        table: "messages",
        sensitive: &["body"],
    },
    Versioned {
        table: "inboxes",
        sensitive: &["summary"],
    },
    Versioned {
        table: "drafts",
        sensitive: &["body", "compensation_body", "ai_prompt", "ai_response"],
    },
    Versioned {
        table: "personas",
        sensitive: &["system_prompt", "guardrail_notes"],
    },
];

/// Look up the [`Versioned`] descriptor for a table, if it is versioned.
pub fn versioned_for(table: &str) -> Option<&'static Versioned> {
    VERSIONED.iter().find(|v| v.table == table)
}

/// Whether a paper-trail action type that mutates rows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VersionAction {
    Create,
    Update,
    Destroy,
}

impl VersionAction {
    pub const fn as_str(self) -> &'static str {
        match self {
            VersionAction::Create => "create",
            VersionAction::Update => "update",
            VersionAction::Destroy => "destroy",
        }
    }
}

fn redacted_value(field: &str, value: &Value, sensitive: &[&str]) -> Value {
    if sensitive.contains(&field) {
        Value::String(REDACTED.to_string())
    } else {
        value.clone()
    }
}

/// Compute the `changes` map for a version row.
///
/// - `before = None` → create: every `after` attribute is a change.
/// - `before = Some(..)` → update: only attributes whose value differs.
///
/// Sensitive attribute values are redacted. Returns `None` when nothing
/// changed (changes_only: no version row should be written).
pub fn compute_changes(
    before: Option<&Map<String, Value>>,
    after: &Map<String, Value>,
    sensitive: &[&str],
) -> Option<Map<String, Value>> {
    let mut changes = Map::new();

    match before {
        None => {
            for (k, v) in after {
                changes.insert(k.clone(), redacted_value(k, v, sensitive));
            }
        }
        Some(before) => {
            for (k, v) in after {
                if before.get(k) != Some(v) {
                    changes.insert(k.clone(), redacted_value(k, v, sensitive));
                }
            }
        }
    }

    if changes.is_empty() {
        None
    } else {
        Some(changes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn obj(v: Value) -> Map<String, Value> {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn create_records_all_attributes() {
        let after = obj(json!({"body": "hi", "status": "drafting"}));
        let changes = compute_changes(None, &after, &["body"]).unwrap();
        assert_eq!(changes["body"], json!(REDACTED)); // sensitive redacted
        assert_eq!(changes["status"], json!("drafting"));
        assert_eq!(changes.len(), 2);
    }

    #[test]
    fn update_records_only_changed() {
        let before = obj(json!({"body": "hi", "status": "drafting", "ai_model": "m"}));
        let after = obj(json!({"body": "hi", "status": "approved", "ai_model": "m"}));
        let changes = compute_changes(Some(&before), &after, &["body"]).unwrap();
        assert_eq!(changes.len(), 1);
        assert_eq!(changes["status"], json!("approved"));
    }

    #[test]
    fn redacts_changed_sensitive_field() {
        let before = obj(json!({"body": "old"}));
        let after = obj(json!({"body": "new secret"}));
        let changes = compute_changes(Some(&before), &after, &["body"]).unwrap();
        assert_eq!(changes["body"], json!(REDACTED));
    }

    #[test]
    fn no_change_yields_none() {
        let before = obj(json!({"a": 1, "b": 2}));
        let after = obj(json!({"a": 1, "b": 2}));
        assert!(compute_changes(Some(&before), &after, &[]).is_none());
    }

    #[test]
    fn versioned_lookup_and_sensitivity() {
        let drafts = versioned_for("drafts").unwrap();
        assert!(drafts.sensitive.contains(&"ai_prompt"));
        assert!(versioned_for("actions").is_none()); // actions are NOT versioned
        assert!(versioned_for("audit_events").is_none());
        assert_eq!(VERSIONED.len(), 11);
    }
}
