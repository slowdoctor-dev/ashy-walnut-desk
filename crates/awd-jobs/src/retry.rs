//! Job lifecycle state + the retry-vs-exhausted decision shared by all workers.
//!
//! A worker classifies its outcome as retryable (e.g. `Transient`,
//! `RateLimited`, `Timeout`) or not (`Permanent`, `ContentBlocked`). With
//! attempts remaining, a retryable failure reschedules with the worker's
//! backoff; otherwise the work is driven to its terminal failure transition.

/// Job row state (matches the `jobs.state` CHECK in migration 0006).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobState {
    Available,
    Scheduled,
    Executing,
    Completed,
    Discarded,
}

impl JobState {
    pub const fn as_str(self) -> &'static str {
        match self {
            JobState::Available => "available",
            JobState::Scheduled => "scheduled",
            JobState::Executing => "executing",
            JobState::Completed => "completed",
            JobState::Discarded => "discarded",
        }
    }
}

/// What to do after a worker run that did not succeed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    /// Reschedule after `backoff_secs`.
    Retry { backoff_secs: i64 },
    /// No attempts left (or a non-retryable error): drive the terminal failure.
    Exhausted,
}

/// Decide retry vs exhaust. `attempt` is 1-based; `backoff_secs` is the worker's
/// computed backoff for the *next* attempt.
pub fn decide(retryable: bool, attempt: u32, max_attempts: u32, backoff_secs: i64) -> Decision {
    if retryable && attempt < max_attempts {
        Decision::Retry { backoff_secs }
    } else {
        Decision::Exhausted
    }
}

/// The Oban dedup `unique: [keys: [:action_id, :kind]]` → a `jobs.unique_key`.
pub fn outbound_unique_key(kind: &str, id: &str) -> String {
    format!("outbound:{id}:{kind}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backoff::{generation_backoff, OUTBOUND_MAX_ATTEMPTS};

    #[test]
    fn retryable_with_attempts_left_retries() {
        assert_eq!(
            decide(true, 1, OUTBOUND_MAX_ATTEMPTS, 30),
            Decision::Retry { backoff_secs: 30 }
        );
    }

    #[test]
    fn last_attempt_exhausts_even_if_retryable() {
        assert_eq!(
            decide(true, 5, OUTBOUND_MAX_ATTEMPTS, 7200),
            Decision::Exhausted
        );
    }

    #[test]
    fn non_retryable_exhausts_immediately() {
        assert_eq!(
            decide(false, 1, 3, generation_backoff(1)),
            Decision::Exhausted
        );
    }

    #[test]
    fn unique_key_shape() {
        assert_eq!(outbound_unique_key("action", "abc"), "outbound:abc:action");
        assert_ne!(
            outbound_unique_key("action", "abc"),
            outbound_unique_key("compensation", "abc")
        );
    }

    #[test]
    fn state_strings_match_migration() {
        assert_eq!(JobState::Available.as_str(), "available");
        assert_eq!(JobState::Discarded.as_str(), "discarded");
    }
}
