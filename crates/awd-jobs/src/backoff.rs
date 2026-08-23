//! Per-worker retry backoff schedules + attempt counts, ported exactly from the
//! Oban workers. `attempt` is 1-based (Oban's convention).

/// Outbound send (`outbound_send.ex`): 5 attempts, fixed schedule (seconds).
pub const OUTBOUND_MAX_ATTEMPTS: u32 = 5;
pub const OUTBOUND_BACKOFF: [i64; 5] = [30, 120, 600, 1800, 7200]; // 30s,2m,10m,30m,2h

/// AI generation (`generation_worker.ex`): 3 attempts, exponential.
pub const GENERATION_MAX_ATTEMPTS: u32 = 3;

/// Backoff for the outbound worker. `Some(secs)` for attempts 1..=5, else `None`
/// (Oban falls back to its default beyond the schedule).
pub fn outbound_backoff(attempt: u32) -> Option<i64> {
    if (1..=OUTBOUND_MAX_ATTEMPTS).contains(&attempt) {
        Some(OUTBOUND_BACKOFF[(attempt - 1) as usize])
    } else {
        None
    }
}

/// Backoff for the AI generation worker: `round(2^(attempt-1) * 30)` seconds.
/// (Exact integer arithmetic for the small attempt range.)
pub fn generation_backoff(attempt: u32) -> i64 {
    debug_assert!(attempt > 0);
    30 * 2i64.pow(attempt - 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn outbound_schedule_exact() {
        assert_eq!(outbound_backoff(1), Some(30));
        assert_eq!(outbound_backoff(2), Some(120));
        assert_eq!(outbound_backoff(3), Some(600));
        assert_eq!(outbound_backoff(4), Some(1800));
        assert_eq!(outbound_backoff(5), Some(7200));
        assert_eq!(outbound_backoff(0), None);
        assert_eq!(outbound_backoff(6), None);
    }

    #[test]
    fn generation_schedule_exact() {
        assert_eq!(generation_backoff(1), 30);
        assert_eq!(generation_backoff(2), 60);
        assert_eq!(generation_backoff(3), 120);
    }
}
