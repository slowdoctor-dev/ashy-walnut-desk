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
    /// admin + operator + viewer (the read trio).
    ReadTrio,
    /// admin + operator (`AdminOrOperator`).
    AdminOrOperator,
    /// admin only (`actor_attribute_equals(:role, :admin)`).
    AdminOnly,
    /// background worker only (`FromActionWorker` / `FromGenerationWorker`).
    Worker,
    /// internal caller only (`FromDraftApprove` / `FromActionExecute`).
    Internal,
    /// never allowed (`forbid_if always()`).
    Forbidden,
}

/// Does `role` (a signed-in human actor) satisfy `access`? Worker/Internal are
/// never satisfied by a human role; they're driven by the system.
pub fn authorize(access: Access, role: Role) -> bool {
    match access {
        Access::ReadTrio => role.can_read(),
        Access::AdminOrOperator => role.can_write(),
        Access::AdminOnly => role.is_admin(),
        Access::Worker | Access::Internal | Access::Forbidden => false,
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
        // worker/internal/forbidden: no human role.
        for r in [Role::Admin, Role::Operator, Role::Viewer] {
            assert!(!authorize(Access::Worker, r));
            assert!(!authorize(Access::Internal, r));
            assert!(!authorize(Access::Forbidden, r));
        }
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
