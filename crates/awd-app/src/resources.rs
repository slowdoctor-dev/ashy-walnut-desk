//! Per-resource authorization tables — the `policies` + `field_policies` blocks
//! of every resource other than Draft (which is the typed exemplar in
//! [`crate::draft`]), ported 1:1 from the Elixir source.
//!
//! Each resource becomes a module exposing:
//! - `access(action) -> Access` and `can(action, role) -> bool`
//! - `can_record(action, role, actor_id, owner_id)` for `AdminOrOwner` actions
//! - `field_visibility(field) -> Visibility` + `redact_view(role, &mut row)`
//!
//! Unknown actions default to [`Access::Forbidden`] (deny-by-default).

/// Generate a resource policy module from its action/field tables.
macro_rules! resource_policy {
    (
        $(#[$meta:meta])*
        $name:ident {
            actions { $($act:literal => $acc:expr),+ $(,)? }
            admin_operator_fields { $($aof:literal),* $(,)? }
            admin_only_fields { $($aonly:literal),* $(,)? }
        }
    ) => {
        $(#[$meta])*
        pub mod $name {
            use crate::policy::{authorize, authorize_record, field_visible, Access, Visibility};
            use awd_auth::Role;
            use serde_json::{Map, Value};

            /// Access class for `action` (deny-by-default for unknown actions).
            pub fn access(action: &str) -> Access {
                match action {
                    $($act => $acc,)+
                    _ => Access::Forbidden,
                }
            }

            /// Fields restricted to admin+operator (`field_policy AdminOrOperator`).
            pub const ADMIN_OPERATOR_FIELDS: &[&str] = &[$($aof),*];
            /// Fields restricted to admin only (`field_policy ... :role, :admin`).
            pub const ADMIN_ONLY_FIELDS: &[&str] = &[$($aonly),*];

            pub fn field_visibility(field: &str) -> Visibility {
                if ADMIN_ONLY_FIELDS.contains(&field) {
                    Visibility::AdminOnly
                } else if ADMIN_OPERATOR_FIELDS.contains(&field) {
                    Visibility::AdminOrOperator
                } else {
                    Visibility::Public
                }
            }

            /// Authorize a human `role` for `action` (record-independent).
            pub fn can(action: &str, role: Role) -> bool {
                authorize(access(action), role)
            }

            /// Record-scoped authorize (for `AdminOrOwner` actions). `owner_id`
            /// is the record's owning user id (e.g. `recorded_by_id`, or the row
            /// id for self-access).
            pub fn can_record(action: &str, role: Role, actor_id: &str, owner_id: &str) -> bool {
                authorize_record(access(action), role, actor_id, owner_id)
            }

            /// Drop fields `role` may not see, so raw rows never escape with
            /// sensitive content.
            pub fn redact_view(role: Role, fields: &mut Map<String, Value>) {
                fields.retain(|k, _| field_visible(field_visibility(k), role));
            }
        }
    };
}

// ── Interaction axis ───────────────────────────────────────────────────────

resource_policy! {
    /// `action.ex`. `action_type(:read)` = trio; worker transitions internal.
    action {
        actions {
            "read" => Access::ReadTrio,
            "execute" => Access::AdminOrOperator,
            "register_pending" => Access::Internal,   // FromDraftApprove
            "complete_outbound" => Access::Worker,     // FromActionWorker
            "fail_outbound" => Access::Worker,
        }
        admin_operator_fields { "adapter_response", "error" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `compensation.ex`. Two-step trigger by operator; reset_trigger admin-only.
    compensation {
        actions {
            "read" => Access::ReadTrio,
            "register" => Access::Internal,            // FromDraftApprove
            "initiate_trigger" => Access::AdminOrOperator,
            "trigger" => Access::AdminOrOperator,
            "complete_send" => Access::Worker,         // FromActionWorker
            "fail_send" => Access::Worker,
            "reset_trigger" => Access::AdminOnly,
        }
        admin_operator_fields { "body", "adapter_response", "error" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `inbox.ex`. record_inbound = webhook; mark_executed = internal (Action.execute).
    inbox {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "record_inbox" => Access::AdminOrOperator,
            "record_inbound" => Access::Webhook,       // FromInboundWebhook
            "mark_drafting" => Access::AdminOrOperator,
            "mark_executed" => Access::Internal,       // FromActionExecute
            "dismiss" => Access::AdminOrOperator,
            "edit_summary" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "summary" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `channel.ex`. All mutations admin-only.
    channel {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "register_channel" => Access::AdminOnly,
            "disable" => Access::AdminOnly,
            "enable" => Access::AdminOnly,
            "archive" => Access::AdminOnly,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "adapter_module" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `conversation.ex`.
    conversation {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "open_conversation" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "subject" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `message.ex`.
    message {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "record_message" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "body" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `audit_event.ex`. Admin-only read + admin-only payload (append-only).
    audit_event {
        actions { "read" => Access::AdminOnly }
        admin_operator_fields {}
        admin_only_fields { "payload" }
    }
}

resource_policy! {
    /// `inbound_delivery.ex`. Admin-only read; record_delivery = webhook.
    inbound_delivery {
        actions {
            "read" => Access::AdminOnly,
            "record_delivery" => Access::Webhook,      // FromInboundWebhook
        }
        admin_operator_fields {}
        admin_only_fields { "provider_message_id" }
    }
}

// ── Identity axis ────────────────────────────────────────────────────────

resource_policy! {
    /// `identity.ex`. register_provisional = webhook; raw identifier admin-only.
    identity {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "register_identity" => Access::AdminOrOperator,
            "register_provisional" => Access::Webhook, // FromInboundWebhook
            "update_profile" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields {}
        admin_only_fields { "primary_identifier", "primary_identifier_hash" }
    }
}

resource_policy! {
    /// `event.ex`.
    event {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "record_event" => Access::AdminOrOperator,
            "update_event" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "summary", "body" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `appointment.ex`.
    appointment {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "schedule_appointment" => Access::AdminOrOperator,
            "reschedule" => Access::AdminOrOperator,
            "cancel" => Access::AdminOrOperator,
            "complete" => Access::AdminOrOperator,
            "archive" => Access::AdminOrOperator,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "summary" }
        admin_only_fields {}
    }
}

resource_policy! {
    /// `note.ex`. edit_note/archive = admin OR the recording operator (owner).
    note {
        actions {
            "read" => Access::ReadTrio,
            "read_with_archived" => Access::AdminOnly,
            "record_note" => Access::AdminOrOperator,
            "edit_note" => Access::AdminOrOwner,       // admin or recorded_by_id
            "archive" => Access::AdminOrOwner,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields { "body" }
        admin_only_fields {}
    }
}

// ── Knowledge axis ───────────────────────────────────────────────────────

resource_policy! {
    /// `persona.ex`. NOTE: read is admin+operator (NOT the viewer trio); all
    /// create/update/archive/recover are admin-only; prompt content admin-only.
    persona {
        actions {
            "read" => Access::AdminOrOperator,
            "read_with_archived" => Access::AdminOnly,
            "create" => Access::AdminOnly,
            "update" => Access::AdminOnly,
            "archive" => Access::AdminOnly,
            "recover" => Access::AdminOnly,
        }
        admin_operator_fields {}
        admin_only_fields { "system_prompt", "disclosure_text", "guardrail_notes", "model_override" }
    }
}

// ── Accounts ───────────────────────────────────────────────────────────────

resource_policy! {
    /// `user.ex`. read = admin OR self (owner = row id); magic-link actions are
    /// public; `register` is forbidden (users are created via sign-in flow).
    user {
        actions {
            "read" => Access::AdminOrOwner,            // admin or id == actor.id
            "assign_role" => Access::AdminOnly,
            "register" => Access::Forbidden,
            "request_magic_link" => Access::Public,
            "sign_in_with_magic_link" => Access::Public,
        }
        admin_operator_fields {}
        admin_only_fields {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use awd_auth::Role;
    use serde_json::json;

    #[test]
    fn four_stage_chain_callers() {
        // Action: operator executes; workers complete; viewers read only.
        assert!(action::can("execute", Role::Operator));
        assert!(!action::can("execute", Role::Viewer));
        assert!(!action::can("complete_outbound", Role::Admin)); // worker-only
        assert!(action::can("read", Role::Viewer));
        // register_pending is internal — no human role.
        assert!(!action::can("register_pending", Role::Admin));

        // Compensation: reset_trigger admin-only; register internal.
        assert!(compensation::can("reset_trigger", Role::Admin));
        assert!(!compensation::can("reset_trigger", Role::Operator));
        assert!(!compensation::can("register", Role::Admin));

        // Inbox: record_inbound is webhook-only; mark_executed internal.
        assert!(!inbox::can("record_inbound", Role::Admin));
        assert!(!inbox::can("mark_executed", Role::Operator));
        assert!(inbox::can("dismiss", Role::Operator));
    }

    #[test]
    fn admin_only_resources() {
        for a in [
            "register_channel",
            "disable",
            "enable",
            "archive",
            "recover",
        ] {
            assert!(channel::can(a, Role::Admin));
            assert!(!channel::can(a, Role::Operator));
        }
        assert!(audit_event::can("read", Role::Admin));
        assert!(!audit_event::can("read", Role::Operator)); // not even operators
        assert!(inbound_delivery::can("read", Role::Admin));
        assert!(!inbound_delivery::can("record_delivery", Role::Admin)); // webhook
    }

    #[test]
    fn identity_and_webhook_provisioning() {
        assert!(identity::can("register_identity", Role::Operator));
        assert!(!identity::can("register_provisional", Role::Operator)); // webhook
        assert!(identity::can("read", Role::Viewer));
        // raw identifier is admin-only at the field level.
        assert_eq!(
            identity::field_visibility("primary_identifier"),
            crate::policy::Visibility::AdminOnly
        );
    }

    #[test]
    fn note_owner_based_actions() {
        // owner (operator who recorded it) may edit; a different operator may not; admin always.
        assert!(note::can_record("edit_note", Role::Operator, "op1", "op1"));
        assert!(!note::can_record("edit_note", Role::Operator, "op1", "op2"));
        assert!(note::can_record("archive", Role::Admin, "admin", "op2"));
        // record-independent `can` only grants admins for owner actions.
        assert!(!note::can("edit_note", Role::Operator));
        assert!(note::can("edit_note", Role::Admin));
    }

    #[test]
    fn persona_excludes_viewers_and_hides_prompt() {
        assert!(persona::can("read", Role::Operator));
        assert!(!persona::can("read", Role::Viewer)); // KEY: no viewer trio here
        assert!(persona::can("create", Role::Admin));
        assert!(!persona::can("create", Role::Operator));
        assert_eq!(
            persona::field_visibility("system_prompt"),
            crate::policy::Visibility::AdminOnly
        );
    }

    #[test]
    fn user_self_read_and_public_actions() {
        // self-read ok; reading another user requires admin.
        assert!(user::can_record("read", Role::Operator, "u1", "u1"));
        assert!(!user::can_record("read", Role::Operator, "u1", "u2"));
        assert!(user::can_record("read", Role::Admin, "admin", "u2"));
        // magic-link actions are public; register is forbidden.
        assert!(user::can("request_magic_link", Role::Viewer));
        assert!(!user::can("register", Role::Admin));
    }

    #[test]
    fn redaction_hides_restricted_fields_from_viewers() {
        // audit payload hidden from a (hypothetical) non-admin reader.
        let mut row = json!({"id": "a1", "event_type": "draft_approved", "payload": {"x": 1}})
            .as_object()
            .unwrap()
            .clone();
        audit_event::redact_view(Role::Operator, &mut row);
        assert!(!row.contains_key("payload"));
        assert!(row.contains_key("event_type"));

        // compensation body hidden from viewer, kept for operator.
        let comp = json!({"id": "c1", "status": "registered", "body": "secret", "error": "boom"});
        let mut as_viewer = comp.as_object().unwrap().clone();
        compensation::redact_view(Role::Viewer, &mut as_viewer);
        assert!(!as_viewer.contains_key("body"));
        assert!(!as_viewer.contains_key("error"));
        assert!(as_viewer.contains_key("status"));
    }
}
