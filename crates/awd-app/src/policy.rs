//! The authorization layer — the generic primitive that replaces Ash `policies`
//! and `field_policies`. Each Ash `policy action(:x)` becomes an [`Access`]
//! classification consulted by `authorize`; each `field_policy` becomes a
//! [`Visibility`] consulted by the role-aware DTO serializer.
//!
//! Internal/worker-only actions (Ash's `FromActionWorker` / `FromDraftApprove`
//! context checks) map to [`Access::Worker`] / [`Access::Internal`], which no
//! human role satisfies — in the real orchestration those transitions are also
//! `pub(crate)`, so the compiler enforces what the runtime policy did.

use awd_auth::Role;

/// How an action is gated (mirrors the `authorize_if(..)` patterns).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Access {
    /// anyone, including unauthenticated (`authorize_if(always())` on a public
    /// action — e.g. request/consume magic link).
    Public,
    /// admin + operator + viewer (the read trio).
    ReadTrio,
    /// admin + operator (`AdminOrOperator`).
    AdminOrOperator,
    /// admin only (`actor_attribute_equals(:role, :admin)`).
    AdminOnly,
    /// admin OR the record's owner (`… or expr(recorded_by_id == ^actor(:id))`,
    /// and user self-read). Record-scoped — evaluate with [`authorize_record`].
    AdminOrOwner,
    /// background worker only (`FromActionWorker` / `FromGenerationWorker`).
    Worker,
    /// internal caller only (`FromDraftApprove` / `FromActionExecute`).
    Internal,
    /// inbound-webhook system actor only (`FromInboundWebhook`).
    Webhook,
    /// never allowed (`forbid_if always()`).
    Forbidden,
}

/// Does `role` (a signed-in human actor) satisfy `access`? Worker/Internal/
/// Webhook are never satisfied by a human role; they're driven by the system.
/// For [`Access::AdminOrOwner`] this returns the record-independent grant
/// (admins always pass); non-admins must be checked with [`authorize_record`].
pub fn authorize(access: Access, role: Role) -> bool {
    match access {
        Access::Public => true,
        Access::ReadTrio => role.can_read(),
        Access::AdminOrOperator => role.can_write(),
        Access::AdminOnly => role.is_admin(),
        Access::AdminOrOwner => role.is_admin(),
        Access::Worker | Access::Internal | Access::Webhook | Access::Forbidden => false,
    }
}

/// Record-scoped authorization. Identical to [`authorize`] except
/// [`Access::AdminOrOwner`] also admits the actor when they own the record
/// (`actor_id == owner_id`, e.g. `recorded_by_id`, or the row id for self-read).
pub fn authorize_record(access: Access, role: Role, actor_id: &str, owner_id: &str) -> bool {
    match access {
        Access::AdminOrOwner => role.is_admin() || actor_id == owner_id,
        other => authorize(other, role),
    }
}

/// Per-field visibility (mirrors `field_policy`). `Public` is the `:*`
/// `authorize_if(always())` fallback — visible to any reader.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Visibility {
    Public,
    AdminOrOperator,
    AdminOnly,
}

/// Is a field with `vis` visible to `role`? (Assumes read access already
/// granted; this is the per-attribute filter on top.)
pub fn field_visible(vis: Visibility, role: Role) -> bool {
    match vis {
        Visibility::Public => true,
        Visibility::AdminOrOperator => role.can_write(),
        Visibility::AdminOnly => role.is_admin(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_access_matrix() {
        assert!(authorize(Access::ReadTrio, Role::Viewer));
        assert!(!authorize(Access::AdminOrOperator, Role::Viewer));
        assert!(authorize(Access::AdminOrOperator, Role::Operator));
        assert!(!authorize(Access::AdminOnly, Role::Operator));
        assert!(authorize(Access::AdminOnly, Role::Admin));
        // worker/internal/webhook/forbidden: no human role.
        for r in [Role::Admin, Role::Operator, Role::Viewer] {
            assert!(!authorize(Access::Worker, r));
            assert!(!authorize(Access::Internal, r));
            assert!(!authorize(Access::Webhook, r));
            assert!(!authorize(Access::Forbidden, r));
            assert!(authorize(Access::Public, r)); // public: anyone
        }
        // AdminOrOwner without a record: only admins pass.
        assert!(authorize(Access::AdminOrOwner, Role::Admin));
        assert!(!authorize(Access::AdminOrOwner, Role::Operator));
    }

    #[test]
    fn record_scoped_owner_access() {
        // admin always; owner matches; non-owner non-admin denied.
        assert!(authorize_record(
            Access::AdminOrOwner,
            Role::Admin,
            "op1",
            "op2"
        ));
        assert!(authorize_record(
            Access::AdminOrOwner,
            Role::Operator,
            "op1",
            "op1"
        ));
        assert!(!authorize_record(
            Access::AdminOrOwner,
            Role::Operator,
            "op1",
            "op2"
        ));
        // non-owner classes ignore the ids and defer to `authorize`.
        assert!(authorize_record(
            Access::AdminOrOperator,
            Role::Operator,
            "x",
            "y"
        ));
        assert!(!authorize_record(
            Access::AdminOnly,
            Role::Operator,
            "x",
            "x"
        ));
    }

    #[test]
    fn field_visibility_matrix() {
        assert!(field_visible(Visibility::Public, Role::Viewer));
        assert!(!field_visible(Visibility::AdminOrOperator, Role::Viewer));
        assert!(field_visible(Visibility::AdminOrOperator, Role::Operator));
        assert!(!field_visible(Visibility::AdminOnly, Role::Operator));
        assert!(field_visible(Visibility::AdminOnly, Role::Admin));
    }
}
