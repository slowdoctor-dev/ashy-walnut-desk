//! Four-stage record-chain state machines (ADR-016): Inbox → Draft → Action →
//! Compensation. Ports the `StatusTransition` validations + the per-action
//! `from:` lists and policy callers from the Elixir resources.
//!
//! The Elixir `StatusTransition` validation only checks that the *current*
//! status is in the action's `from:` list. Who may invoke the action is
//! enforced separately by Ash policies (`AdminOrOperator`, `FromActionWorker`,
//! `FromGenerationWorker`, `FromActionExecute`, `FromDraftApprove`). We keep
//! both here: `ensure_transition` is the pure status guard, and each table row
//! records the legal [`Caller`] so the `awd-app` authorize layer can consult it
//! (and `pub(crate)` visibility can enforce the internal-only ones).

/// Who is permitted to drive a given transition.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Caller {
    /// Signed-in operator or admin (`AdminOrOperator`).
    Operator,
    /// A background worker only (`FromActionWorker` / `FromGenerationWorker` /
    /// `FromActionExecute`).
    Worker,
    /// Admin only (e.g. `reset_trigger` recovery).
    Admin,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("invalid transition from {from} to {to} (allowed froms: {allowed})")]
pub struct TransitionError {
    pub from: &'static str,
    pub to: &'static str,
    pub allowed: &'static str,
}

/// Implements the shared status-machine surface for one stage enum.
macro_rules! status_machine {
    (
        $(#[$meta:meta])*
        $name:ident { $( $variant:ident => $str:literal ),+ $(,)? }
        transitions = [ $( ($from:ident, $to:ident, $caller:expr) ),* $(,)? ]
        $(unreachable = [ $($unreachable:ident),* $(,)? ])?
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub enum $name { $( $variant ),+ }

        impl $name {
            pub const fn as_str(self) -> &'static str {
                match self { $( $name::$variant => $str ),+ }
            }

            #[allow(clippy::should_implement_trait)] // intentional infallible Option parser
            pub fn from_str(s: &str) -> Option<$name> {
                Some(match s { $( $str => $name::$variant, )+ _ => return None })
            }

            /// `(from, to, caller)` legal transitions. Self-loops that change no
            /// status are included where the Elixir action permits re-running.
            pub const TRANSITIONS: &'static [($name, $name, Caller)] =
                &[ $( ($name::$from, $name::$to, $caller) ),* ];

            /// Pure status guard — mirrors `StatusTransition` (checks `from`).
            pub fn can_transition(self, to: $name) -> bool {
                Self::TRANSITIONS.iter().any(|&(f, t, _)| f == self && t == to)
            }

            /// Callers permitted to drive `self -> to` (empty if illegal).
            pub fn allowed_callers(self, to: $name) -> Vec<Caller> {
                Self::TRANSITIONS
                    .iter()
                    .filter(|&&(f, t, _)| f == self && t == to)
                    .map(|&(_, _, c)| c)
                    .collect()
            }

            pub fn ensure_transition(self, to: $name) -> Result<(), TransitionError> {
                if self.can_transition(to) {
                    Ok(())
                } else {
                    Err(TransitionError { from: self.as_str(), to: to.as_str(), allowed: stringify!($($from)*) })
                }
            }
        }
    };
}

status_machine! {
    /// Stage 1. `inbox.ex`. Created at `:open`. `dismissed` is terminal and
    /// cannot reach `executed`; `executed` is idempotent (worker re-entry).
    Inbox {
        Open => "open",
        Drafting => "drafting",
        Executed => "executed",
        Dismissed => "dismissed",
    }
    transitions = [
        (Open, Drafting, Caller::Operator),
        (Open, Executed, Caller::Worker),
        (Drafting, Executed, Caller::Worker),
        (Executed, Executed, Caller::Worker),
        (Open, Dismissed, Caller::Operator),
        (Drafting, Dismissed, Caller::Operator),
    ]
}

status_machine! {
    /// Stage 2. `draft.ex`. A validator-FAILED generation still lands in
    /// `drafting` (reviewable); only `approve` (Drafting→Approved) is gated by
    /// `ValidatorPassed` in the app layer. `revise` is a Drafting self-loop.
    Draft {
        Generating => "generating",
        Drafting => "drafting",
        Approved => "approved",
        Superseded => "superseded",
        Rejected => "rejected",
    }
    transitions = [
        (Generating, Drafting, Caller::Worker),
        (Generating, Rejected, Caller::Worker),
        (Drafting, Drafting, Caller::Operator),
        (Drafting, Rejected, Caller::Operator),
        (Drafting, Superseded, Caller::Operator),
        (Drafting, Approved, Caller::Operator),
    ]
}

status_machine! {
    /// Stage 3. `action.ex`. Created at `:pending` (internal, `FromDraftApprove`).
    /// `execute` (Pending→Scheduled) runs the 5s `CountdownGuard` in the app
    /// layer. `rolled_back` is in the schema but currently unreachable.
    Action {
        Pending => "pending",
        Scheduled => "scheduled",
        Executed => "executed",
        Failed => "failed",
        RolledBack => "rolled_back",
    }
    transitions = [
        (Pending, Scheduled, Caller::Operator),
        (Scheduled, Executed, Caller::Worker),
        (Scheduled, Failed, Caller::Worker),
        (Pending, Failed, Caller::Worker),
    ]
    unreachable = [RolledBack]
}

status_machine! {
    /// Stage 4. `compensation.ex`. Created at `:registered` (internal). Two-step
    /// trigger: `initiate_trigger` (Registered→Triggering, stamps
    /// `trigger_initiated_at`) then `trigger` (Triggering→Scheduled, runs the
    /// `CompensationCountdownGuard`). `completed` is unreachable (terminal
    /// success is `triggered`). `reset_trigger` is admin-only recovery.
    Compensation {
        Registered => "registered",
        Triggering => "triggering",
        Scheduled => "scheduled",
        Triggered => "triggered",
        Completed => "completed",
        Failed => "failed",
    }
    transitions = [
        (Registered, Triggering, Caller::Operator),
        (Triggering, Scheduled, Caller::Operator),
        (Scheduled, Triggered, Caller::Worker),
        (Scheduled, Failed, Caller::Worker),
        (Triggering, Failed, Caller::Worker),
        (Triggering, Registered, Caller::Admin),
    ]
    unreachable = [Completed]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn str_roundtrips() {
        for s in ["open", "drafting", "executed", "dismissed"] {
            assert_eq!(Inbox::from_str(s).unwrap().as_str(), s);
        }
        assert_eq!(Draft::from_str("approved"), Some(Draft::Approved));
        assert_eq!(Action::from_str("rolled_back"), Some(Action::RolledBack));
        assert_eq!(Compensation::from_str("nope"), None);
    }

    #[test]
    fn inbox_transitions() {
        assert!(Inbox::Open.can_transition(Inbox::Drafting));
        assert!(Inbox::Executed.can_transition(Inbox::Executed)); // idempotent
        assert!(!Inbox::Dismissed.can_transition(Inbox::Executed)); // terminal
        assert!(!Inbox::Open.can_transition(Inbox::Open));
        assert!(Inbox::Open.ensure_transition(Inbox::Drafting).is_ok());
        assert!(Inbox::Dismissed.ensure_transition(Inbox::Executed).is_err());
    }

    #[test]
    fn draft_approve_is_operator_only() {
        assert_eq!(
            Draft::Drafting.allowed_callers(Draft::Approved),
            vec![Caller::Operator]
        );
        assert!(Draft::Generating.can_transition(Draft::Drafting));
        assert_eq!(
            Draft::Generating.allowed_callers(Draft::Drafting),
            vec![Caller::Worker]
        );
        assert!(Draft::Drafting.can_transition(Draft::Drafting)); // revise
        assert!(!Draft::Approved.can_transition(Draft::Drafting));
    }

    #[test]
    fn action_worker_vs_operator() {
        assert_eq!(
            Action::Pending.allowed_callers(Action::Scheduled),
            vec![Caller::Operator]
        );
        assert_eq!(
            Action::Scheduled.allowed_callers(Action::Executed),
            vec![Caller::Worker]
        );
        assert!(!Action::Executed.can_transition(Action::Failed));
        // rolled_back unreachable
        assert!(Action::TRANSITIONS
            .iter()
            .all(|&(_, t, _)| t != Action::RolledBack));
    }

    #[test]
    fn compensation_two_step_and_reset() {
        assert!(Compensation::Registered.can_transition(Compensation::Triggering));
        assert!(Compensation::Triggering.can_transition(Compensation::Scheduled));
        assert_eq!(
            Compensation::Triggering.allowed_callers(Compensation::Registered),
            vec![Caller::Admin]
        );
        // completed unreachable
        assert!(Compensation::TRANSITIONS
            .iter()
            .all(|&(_, t, _)| t != Compensation::Completed));
        // cannot skip the trigger step
        assert!(!Compensation::Registered.can_transition(Compensation::Scheduled));
    }
}
