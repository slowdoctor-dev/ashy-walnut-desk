//! 5-second send countdown (ADR-013). Ports `countdown_guard.ex` and
//! `compensation_countdown_guard.ex`.
//!
//! Both guards reduce to: at least [`COUNTDOWN_SECONDS`] whole seconds must
//! have elapsed since a *server-stamped* reference timestamp
//! (`draft.approved_at` for Action execute; `compensation.trigger_initiated_at`
//! for Compensation trigger). A `None` reference (never stamped) always fails.
//!
//! Uses **integer-second truncation**, matching Elixir's
//! `DateTime.diff(now, ref, :second) >= 5` — NOT rounding. The reference
//! timestamp must always come from server `now()`, never the client (anti-tamper).

use chrono::{DateTime, Utc};

pub const COUNTDOWN_SECONDS: i64 = 5;

/// `true` iff `>= COUNTDOWN_SECONDS` whole seconds elapsed since `reference`.
pub fn countdown_ok(reference: Option<DateTime<Utc>>, now: DateTime<Utc>) -> bool {
    match reference {
        None => false,
        // `num_seconds` truncates toward zero == floor for non-negative
        // durations, matching `DateTime.diff(_, _, :second)`.
        Some(ts) => (now - ts).num_seconds() >= COUNTDOWN_SECONDS,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn at(s: u32, ms: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2026, 6, 5, 12, 0, s).unwrap()
            + chrono::Duration::milliseconds(ms as i64)
    }

    #[test]
    fn nil_reference_never_ok() {
        assert!(!countdown_ok(None, at(30, 0)));
    }

    #[test]
    fn boundary_is_inclusive_and_truncates() {
        let approved = at(0, 0);
        assert!(!countdown_ok(Some(approved), at(4, 999))); // 4.999s -> 4
        assert!(countdown_ok(Some(approved), at(5, 0))); // exactly 5s
        assert!(countdown_ok(Some(approved), at(5, 1))); // 5.001s -> 5
        assert!(!countdown_ok(Some(approved), at(4, 0)));
    }

    #[test]
    fn just_under_full_second_below_five() {
        // 4.0s elapsed -> 4 -> not ok
        assert!(!countdown_ok(Some(at(0, 500)), at(4, 499)));
    }
}
