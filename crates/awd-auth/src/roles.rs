//! Role model + the first-user-admin election. Ports the `:role` enum,
//! `AdminOrOperator` check, and `AssignFirstUserAdmin.choose_role/0`.

/// User roles (matches the `users.role` CHECK).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// Full read/write + user management + archive recovery.
    Admin,
    /// Most write actions (drafts, sends, compensation); no token expunge / user assign.
    Operator,
    /// Read-only (status, not bodies/prompts).
    Viewer,
    /// Webhook actor only (inbound intake); cannot sign in.
    System,
}

impl Role {
    pub const fn as_str(self) -> &'static str {
        match self {
            Role::Admin => "admin",
            Role::Operator => "operator",
            Role::Viewer => "viewer",
            Role::System => "system",
        }
    }

    #[allow(clippy::should_implement_trait)] // intentional infallible Option parser
    pub fn from_str(s: &str) -> Option<Role> {
        Some(match s {
            "admin" => Role::Admin,
            "operator" => Role::Operator,
            "viewer" => Role::Viewer,
            "system" => Role::System,
            _ => return None,
        })
    }

    /// `AdminOrOperator` check — admits write actions.
    pub fn can_write(self) -> bool {
        matches!(self, Role::Admin | Role::Operator)
    }

    /// The admin+operator+viewer read trio.
    pub fn can_read(self) -> bool {
        matches!(self, Role::Admin | Role::Operator | Role::Viewer)
    }

    pub fn is_admin(self) -> bool {
        matches!(self, Role::Admin)
    }

    /// The system actor (webhook intake) cannot sign in.
    pub fn can_sign_in(self) -> bool {
        !matches!(self, Role::System)
    }
}

/// Elect the role for a newly registering user (`choose_role/0` + ADR-024):
/// the first **human** signup is admin; the boot-time `:system` actor doesn't
/// count. On the admin-unique-index retry path, force operator.
pub fn choose_role(has_existing_non_system_user: bool, is_admin_index_retry: bool) -> Role {
    if is_admin_index_retry || has_existing_non_system_user {
        Role::Operator
    } else {
        Role::Admin
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn role_strings_roundtrip() {
        for r in [Role::Admin, Role::Operator, Role::Viewer, Role::System] {
            assert_eq!(Role::from_str(r.as_str()), Some(r));
        }
        assert_eq!(Role::from_str("nope"), None);
    }

    #[test]
    fn capability_matrix() {
        assert!(Role::Admin.can_write() && Role::Admin.can_read() && Role::Admin.is_admin());
        assert!(
            Role::Operator.can_write() && Role::Operator.can_read() && !Role::Operator.is_admin()
        );
        assert!(!Role::Viewer.can_write() && Role::Viewer.can_read());
        assert!(!Role::System.can_sign_in());
        assert!(
            Role::Admin.can_sign_in() && Role::Operator.can_sign_in() && Role::Viewer.can_sign_in()
        );
    }

    #[test]
    fn first_human_is_admin_rest_operators() {
        assert_eq!(choose_role(false, false), Role::Admin); // no prior humans
        assert_eq!(choose_role(true, false), Role::Operator); // someone exists
        assert_eq!(choose_role(false, true), Role::Operator); // admin-index retry
    }
}
