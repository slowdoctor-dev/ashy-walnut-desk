//! Draft action authorization + field visibility — the concrete table for the
//! `Draft` resource, ported from `draft.ex`'s `policies` and `field_policies`.
//! Other resources follow the same shape (one table each).

use awd_auth::Role;
use serde_json::{Map, Value};

use crate::policy::{authorize, field_visible, Access, Visibility};

/// The Draft actions (one per `policy action(:x)`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DraftAction {
    Read,
    ReadWithArchived,
    ComposeDraft,
    Revise,
    Reject,
    Supersede,
    Approve,
    Generate,
    CompleteGeneration,
    FailGeneration,
    BackdateApprovalForTests,
    Archive,
    Recover,
}

/// The access class for each Draft action (exact port of `draft.ex` policies).
pub fn access(action: DraftAction) -> Access {
    use DraftAction::*;
    match action {
        Read => Access::ReadTrio,
        ReadWithArchived => Access::AdminOnly,
        ComposeDraft | Revise | Reject | Supersede | Approve | Generate | Archive => {
            Access::AdminOrOperator
        }
        CompleteGeneration | FailGeneration => Access::Worker,
        BackdateApprovalForTests => Access::Forbidden,
        Recover => Access::AdminOnly,
    }
}

/// Authorize a human `role` for a Draft `action`.
pub fn can(action: DraftAction, role: Role) -> bool {
    authorize(access(action), role)
}

/// Fields restricted to admin+operator (`field_policy ... authorize_if(AdminOrOperator)`):
/// message bodies, AI prompt/response, model, and validator output. Everything
/// else is the `:*` public fallback.
pub const DRAFT_ADMIN_OPERATOR_FIELDS: &[&str] = &[
    "body",
    "compensation_body",
    "ai_prompt",
    "ai_response",
    "ai_model",
    "ai_validator_output",
];

/// Visibility class for a Draft field.
pub fn field_visibility(field: &str) -> Visibility {
    if DRAFT_ADMIN_OPERATOR_FIELDS.contains(&field) {
        Visibility::AdminOrOperator
    } else {
        Visibility::Public
    }
}

/// Redact a Draft row for `role`: drop fields the role can't see (so raw rows
/// never escape with sensitive content). Mutates the JSON object in place.
pub fn redact_view(role: Role, fields: &mut Map<String, Value>) {
    fields.retain(|k, _| field_visible(field_visibility(k), role));
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn operator_can_act_but_not_admin_only() {
        assert!(can(DraftAction::Approve, Role::Operator));
        assert!(can(DraftAction::Generate, Role::Operator));
        assert!(!can(DraftAction::Recover, Role::Operator)); // admin only
        assert!(!can(DraftAction::ReadWithArchived, Role::Operator));
    }

    #[test]
    fn viewer_can_read_only() {
        assert!(can(DraftAction::Read, Role::Viewer));
        assert!(!can(DraftAction::Approve, Role::Viewer));
        assert!(!can(DraftAction::Revise, Role::Viewer));
    }

    #[test]
    fn workers_and_forbidden_never_authorized_for_humans() {
        for r in [Role::Admin, Role::Operator, Role::Viewer] {
            assert!(!can(DraftAction::CompleteGeneration, r));
            assert!(!can(DraftAction::FailGeneration, r));
            assert!(!can(DraftAction::BackdateApprovalForTests, r));
        }
    }

    #[test]
    fn admin_can_recover_and_read_archived() {
        assert!(can(DraftAction::Recover, Role::Admin));
        assert!(can(DraftAction::ReadWithArchived, Role::Admin));
    }

    #[test]
    fn viewer_view_redacts_sensitive_fields() {
        let mut row = json!({
            "id": "d1",
            "status": "drafting",
            "body": "secret draft text",
            "ai_model": "claude-sonnet-4-6",
            "ai_validator_output": {"passed?": true},
            "inbox_id": "ib1"
        })
        .as_object()
        .unwrap()
        .clone();

        // operator keeps everything
        let mut op = row.clone();
        redact_view(Role::Operator, &mut op);
        assert!(op.contains_key("body"));
        assert!(op.contains_key("ai_model"));

        // viewer loses body + ai_* but keeps status/id/inbox_id
        redact_view(Role::Viewer, &mut row);
        assert!(!row.contains_key("body"));
        assert!(!row.contains_key("ai_model"));
        assert!(!row.contains_key("ai_validator_output"));
        assert!(row.contains_key("status"));
        assert!(row.contains_key("id"));
        assert!(row.contains_key("inbox_id"));
    }
}
