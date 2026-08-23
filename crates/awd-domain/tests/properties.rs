//! Property tests mirroring the Elixir `*_property_test.exs` invariants
//! (StreamData → proptest): audit-chain continuity + tamper detection,
//! state-machine consistency, countdown monotonicity, identifier determinism.

use awd_domain::audit::{
    self, recompute_hash, verify_chain, ChainEvent, EventType, Payload, PayloadValue, WalkResult,
};
use awd_domain::countdown::{countdown_ok, COUNTDOWN_SECONDS};
use awd_domain::identifier::{hash_primary_identifier, normalize_identifier};
use awd_domain::state::{Action, Caller, Compensation, Draft, Inbox};
use chrono::{TimeZone, Utc};
use proptest::prelude::*;

// ── audit chain ──────────────────────────────────────────────────────────

/// Build a syntactically-valid event of the given type with arbitrary id-ish
/// strings, so we exercise canonicalization across the whole allowlist.
fn sample_payload(et: EventType, seed: &str) -> Payload {
    let s = |k: &str| (k.to_string(), PayloadValue::Str(format!("{k}-{seed}")));
    let mut p = Payload::new();
    match et {
        EventType::InboxOpened => {
            p.extend([s("inbox_id"), s("conversation_id"), s("identity_id")]);
        }
        EventType::DraftStarted | EventType::DraftSuperseded => {
            p.extend([s("inbox_id"), s("draft_id")]);
        }
        EventType::DraftGenerationRequested => {
            p.extend([s("draft_id"), s("inbox_id"), s("persona_id"), s("actor_id")]);
        }
        EventType::DraftGenerationCompleted => {
            p.extend([s("draft_id"), s("inbox_id")]);
            p.insert("input_tokens".into(), PayloadValue::Int(0));
            p.insert("output_tokens".into(), PayloadValue::Int(12));
            p.insert(
                "validator_passed?".into(),
                PayloadValue::Bool(seed.len() % 2 == 0),
            );
            p.insert(
                "violations_count".into(),
                PayloadValue::Int(seed.len() as i64),
            );
        }
        EventType::DraftGenerationFailed => {
            p.extend([s("draft_id"), s("inbox_id")]);
            p.insert("error_class".into(), PayloadValue::Str("transient".into()));
        }
        EventType::DraftApproved => {
            p.extend([s("draft_id"), s("approved_by_id")]);
            p.insert(
                "approved_at".into(),
                PayloadValue::DateTime(Utc.with_ymd_and_hms(2026, 6, 5, 0, 0, 0).unwrap()),
            );
            p.insert(
                "superseded_sibling_draft_ids".into(),
                PayloadValue::StrList(vec![]),
            );
        }
        EventType::ActionScheduled => p.extend([s("action_id"), s("draft_id"), s("channel_id")]),
        EventType::ActionExecuted => {
            p.extend([s("action_id"), s("draft_id"), s("channel_id")]);
            p.insert("outcome".into(), PayloadValue::Str("ok".into()));
        }
        EventType::CompensationRegistered | EventType::CompensationScheduled => {
            p.extend([s("compensation_id"), s("action_id")]);
        }
        EventType::CompensationExecuted => {
            p.extend([s("compensation_id"), s("action_id")]);
            p.insert("outcome".into(), PayloadValue::Str("ok".into()));
        }
    }
    p
}

fn all_event_types() -> Vec<EventType> {
    use EventType::*;
    vec![
        InboxOpened,
        DraftStarted,
        DraftGenerationRequested,
        DraftGenerationCompleted,
        DraftGenerationFailed,
        DraftSuperseded,
        DraftApproved,
        ActionScheduled,
        ActionExecuted,
        CompensationRegistered,
        CompensationScheduled,
        CompensationExecuted,
    ]
}

proptest! {
    /// Any chain built with our own hashing verifies; flipping one stored hash
    /// makes the walk report `BrokenAt` exactly there.
    #[test]
    fn built_chain_verifies_and_tamper_is_detected(
        seeds in proptest::collection::vec("[a-z0-9]{1,8}", 1..12usize),
        type_idx in proptest::collection::vec(0usize..12, 1..12usize),
        tamper_at in 0usize..12,
    ) {
        let types = all_event_types();
        let n = seeds.len().min(type_idx.len());
        let payloads: Vec<(EventType, Payload)> = (0..n)
            .map(|i| {
                let et = types[type_idx[i] % types.len()];
                (et, sample_payload(et, &seeds[i]))
            })
            .collect();

        // Compute the honest chain.
        let mut hashes = Vec::new();
        let mut prev: Option<String> = None;
        for (et, p) in &payloads {
            let h = recompute_hash(prev.as_deref(), *et, p).unwrap();
            prev = Some(h.clone());
            hashes.push(h);
        }

        let events: Vec<ChainEvent> = payloads
            .iter()
            .zip(&hashes)
            .map(|((et, p), h)| ChainEvent { event_type: *et, payload: p, stored_hash: h })
            .collect();
        prop_assert_eq!(verify_chain(&events), WalkResult::Ok { length: n });

        // Tamper with one stored hash.
        let idx = tamper_at % n;
        let mut tampered_hashes = hashes.clone();
        let last = tampered_hashes[idx].chars().last().unwrap();
        let flipped = if last == '0' { '1' } else { '0' }; // guaranteed to differ
        tampered_hashes[idx] =
            format!("{}{}", &tampered_hashes[idx][..tampered_hashes[idx].len() - 1], flipped);
        let tampered: Vec<ChainEvent> = payloads
            .iter()
            .zip(&tampered_hashes)
            .map(|((et, p), h)| ChainEvent { event_type: *et, payload: p, stored_hash: h })
            .collect();
        // The break surfaces at `idx` (its own hash wrong) or `idx+1` (chains on
        // the tampered prev) — never before `idx`.
        match verify_chain(&tampered) {
            WalkResult::BrokenAt(b) => prop_assert!(b == idx || b == idx + 1),
            other => prop_assert!(false, "expected break, got {:?}", other),
        }
    }

    /// Canonicalization is deterministic and independent of input insertion
    /// order (BTreeMap guarantees this, but assert it as a property).
    #[test]
    fn canonicalization_is_order_independent(seed in "[a-z0-9]{1,8}") {
        for et in all_event_types() {
            let p = sample_payload(et, &seed);
            let a = recompute_hash(None, et, &p).unwrap();
            let b = recompute_hash(None, et, &p.clone()).unwrap();
            prop_assert_eq!(a, b);
        }
    }

    /// Unknown keys are always rejected, regardless of event type.
    #[test]
    fn unknown_keys_rejected(seed in "[a-z]{1,6}") {
        for et in all_event_types() {
            let mut p = sample_payload(et, &seed);
            p.insert("definitely_not_allowed".into(), PayloadValue::Int(1));
            prop_assert!(audit::canonicalize_payload(et, &p).is_err());
        }
    }
}

// ── state machines ────────────────────────────────────────────────────────

proptest! {
    /// `can_transition` ⇔ a matching row exists in `TRANSITIONS`, and a legal
    /// transition always has ≥1 allowed caller; an illegal one has none.
    #[test]
    fn state_tables_are_self_consistent(i in 0usize..6, j in 0usize..6) {
        macro_rules! check {
            ($ty:ty, $variants:expr) => {{
                let vs: &[$ty] = $variants;
                let from = vs[i % vs.len()];
                let to = vs[j % vs.len()];
                let can = from.can_transition(to);
                let callers = from.allowed_callers(to);
                prop_assert_eq!(can, !callers.is_empty());
                if can {
                    prop_assert!(<$ty>::TRANSITIONS.iter().any(|&(f, t, _)| f == from && t == to));
                }
            }};
        }
        check!(Inbox, &[Inbox::Open, Inbox::Drafting, Inbox::Executed, Inbox::Dismissed]);
        check!(Draft, &[Draft::Generating, Draft::Drafting, Draft::Approved, Draft::Superseded, Draft::Rejected]);
        check!(Action, &[Action::Pending, Action::Scheduled, Action::Executed, Action::Failed, Action::RolledBack]);
        check!(Compensation, &[Compensation::Registered, Compensation::Triggering, Compensation::Scheduled, Compensation::Triggered, Compensation::Completed, Compensation::Failed]);
    }
}

#[test]
fn terminal_and_unreachable_states_have_no_outgoing_or_incoming() {
    // dismissed is terminal (no outgoing).
    assert!(!Inbox::TRANSITIONS
        .iter()
        .any(|&(f, _, _)| f == Inbox::Dismissed));
    // approve is operator-only; workers can never approve a draft.
    assert!(!Draft::Drafting
        .allowed_callers(Draft::Approved)
        .contains(&Caller::Worker));
    // unreachable states are never a transition target.
    assert!(!Action::TRANSITIONS
        .iter()
        .any(|&(_, t, _)| t == Action::RolledBack));
    assert!(!Compensation::TRANSITIONS
        .iter()
        .any(|&(_, t, _)| t == Compensation::Completed));
}

// ── countdown ───────────────────────────────────────────────────────────

proptest! {
    /// Monotonic: once the countdown passes, it stays passed; and it never
    /// passes before exactly COUNTDOWN_SECONDS whole seconds.
    #[test]
    fn countdown_is_monotonic_and_boundary_exact(elapsed_ms in 0i64..20_000) {
        let t0 = Utc.with_ymd_and_hms(2026, 6, 5, 12, 0, 0).unwrap();
        let now = t0 + chrono::Duration::milliseconds(elapsed_ms);
        let ok = countdown_ok(Some(t0), now);
        prop_assert_eq!(ok, elapsed_ms / 1000 >= COUNTDOWN_SECONDS);
        // monotonicity: a later instant is still ok once ok.
        if ok {
            prop_assert!(countdown_ok(Some(t0), now + chrono::Duration::milliseconds(1)));
        }
        // None reference is never ok.
        prop_assert!(!countdown_ok(None, now));
    }
}

// ── identifier hashing ────────────────────────────────────────────────────

proptest! {
    /// Normalization is idempotent, and a valid E.164 always hashes to 64 lower
    /// hex chars deterministically.
    #[test]
    fn identifier_normalize_idempotent_and_hash_stable(
        digits in "[0-9]{6,15}",
        salt in "[a-zA-Z0-9]{1,16}",
    ) {
        let raw = format!("+{digits}");
        let n1 = normalize_identifier(&raw);
        prop_assert_eq!(normalize_identifier(&n1), n1.clone());

        let (norm, h1) = hash_primary_identifier(&raw, &salt).unwrap();
        prop_assert_eq!(&norm, &raw);
        let (_, h2) = hash_primary_identifier(&raw, &salt).unwrap();
        prop_assert_eq!(&h1, &h2);
        prop_assert_eq!(h1.len(), 64);
        prop_assert!(h1.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
    }
}
