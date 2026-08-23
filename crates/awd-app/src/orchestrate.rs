//! Orchestration core — the functional half of the Ash *actions* for the
//! four-stage chain (Draft.approve → Action.execute → Compensation
//! initiate_trigger/trigger), as **pure plan functions**.
//!
//! Each `plan_*` function takes the already-loaded state + the inputs a DB shell
//! would resolve (channel id, generated ids/keys, the prev audit hash from the
//! `FOR UPDATE` lock, sibling ids) and returns an **effects plan**: the row
//! updates/creates, the chained audit-event appends (hashes computed here via
//! [`awd_domain::audit`]), and any job to enqueue. No I/O, no async — the
//! deferred shell just loads, locks, and persists the plan in one transaction.
//!
//! This is where the load-bearing invariants live and are tested: the validator
//! approval gate, the 5-second countdown re-check, the status transitions, the
//! compensation-at-approval pairing, sibling supersession, and the audit chain.

use awd_auth::Role;
use awd_domain::audit::{self, EventType, Payload, PayloadValue};
use awd_domain::countdown::countdown_ok;
use awd_domain::state::{Action as ActionStatus, Compensation as CompStatus, Draft as DraftStatus};
use chrono::{DateTime, Utc};
use serde_json::Value;
use uuid::Uuid;

use crate::resources;

/// A signed-in actor.
#[derive(Debug, Clone, Copy)]
pub struct Actor {
    pub id: Uuid,
    pub role: Role,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AppError {
    #[error("not authorized for this action")]
    Unauthorized,
    #[error("draft is not in `drafting` (already approved/superseded by a concurrent caller?)")]
    DraftNotDrafting,
    #[error("AI validator output did not pass; cannot approve")]
    ValidatorNotPassed,
    #[error("draft failed the honest-framing check at approval")]
    HonestFramingFailed,
    #[error("compensation_body is required when approving a draft")]
    CompensationBodyRequired,
    #[error("invalid status transition")]
    InvalidTransition,
    #[error("5-second countdown not yet elapsed")]
    CountdownViolation,
    #[error("audit canonicalization error: {0}")]
    Audit(#[from] audit::AuditError),
}

/// One hash-chained audit event the shell must INSERT (in order).
#[derive(Debug, Clone, PartialEq)]
pub struct AuditAppend {
    pub event_type: EventType,
    pub payload: Payload,
    pub prev_hash: Option<String>,
    pub hash: String,
}

/// A job to enqueue (in the same transaction as the row writes).
#[derive(Debug, Clone, PartialEq)]
pub struct JobEnqueue {
    pub queue: &'static str,
    pub args: Value,
    pub unique_key: String,
}

/// Chain a sequence of `(event_type, payload)` off `prev`, computing each hash
/// exactly as [`awd_domain::audit`] (and the verifier) does.
fn chain(
    prev: Option<String>,
    events: Vec<(EventType, Payload)>,
) -> Result<Vec<AuditAppend>, AppError> {
    let mut out = Vec::with_capacity(events.len());
    let mut prev = prev;
    for (event_type, payload) in events {
        let hash = audit::recompute_hash(prev.as_deref(), event_type, &payload)?;
        out.push(AuditAppend {
            event_type,
            payload,
            prev_hash: prev.clone(),
            hash: hash.clone(),
        });
        prev = Some(hash);
    }
    Ok(out)
}

fn id(uuid: Uuid) -> PayloadValue {
    PayloadValue::Str(uuid.to_string())
}

/// The approval gate (`ValidatorPassed`): AI output must report `passed? == true`;
/// otherwise (no AI output) a manual draft must pass the honest-framing check.
fn validator_gate(ai_validator_output: Option<&Value>, body: &str) -> Result<(), AppError> {
    match ai_validator_output {
        Some(v) => {
            if v.get("passed?").and_then(Value::as_bool) == Some(true) {
                Ok(())
            } else {
                Err(AppError::ValidatorNotPassed)
            }
        }
        None => {
            if awd_safety::baseline::honest_framing_hit(body).is_none() {
                Ok(())
            } else {
                Err(AppError::HonestFramingFailed)
            }
        }
    }
}

// ── Draft.approve ────────────────────────────────────────────────────────

/// Loaded draft state needed to plan an approval.
#[derive(Debug, Clone)]
pub struct DraftState {
    pub id: Uuid,
    pub inbox_id: Uuid,
    pub status: DraftStatus,
    pub body: String,
    pub compensation_body: Option<String>,
    pub ai_validator_output: Option<Value>,
}

/// Everything the shell resolves before calling [`plan_approve`].
pub struct ApproveInput {
    pub draft: DraftState,
    pub actor: Actor,
    pub now: DateTime<Utc>,
    /// `compensation_body` argument from the request (falls back to the draft's).
    pub compensation_body_arg: Option<String>,
    /// Resolved via drafts→inboxes→conversations (`Locks::resolve_channel_for_draft`).
    pub channel_id: Uuid,
    /// Shell-generated.
    pub new_action_id: Uuid,
    pub new_compensation_id: Uuid,
    /// `"action-" + uuid` (stamped at register_pending).
    pub new_action_idempotency_key: String,
    /// Other `drafting` drafts in the same inbox (created_at asc) — superseded.
    pub sibling_drafting_ids: Vec<Uuid>,
    /// From `Locks::lock_prev_audit_hash(chain_topic)`.
    pub prev_audit_hash: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DraftApproveUpdate {
    pub status: DraftStatus,
    pub approved_at: DateTime<Utc>,
    pub approved_by_id: Uuid,
    pub compensation_body: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ActionCreate {
    pub id: Uuid,
    pub draft_id: Uuid,
    pub channel_id: Uuid,
    pub status: ActionStatus,
    pub outbound_idempotency_key: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CompensationCreate {
    pub id: Uuid,
    pub action_id: Uuid,
    pub body: String,
    pub status: CompStatus,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ApprovePlan {
    pub chain_topic: String,
    pub draft_update: DraftApproveUpdate,
    pub action_create: ActionCreate,
    pub compensation_create: CompensationCreate,
    pub superseded_draft_ids: Vec<Uuid>,
    /// `[draft_approved, compensation_registered]`, hash-chained.
    pub audit: Vec<AuditAppend>,
}

/// Plan `Draft.approve` (the `CompensationAtApproval` + supersede + ChainLink
/// orchestration), as a pure function.
pub fn plan_approve(input: ApproveInput) -> Result<ApprovePlan, AppError> {
    // policy: action(:approve) authorize_if(AdminOrOperator)
    if !crate::draft::can(crate::draft::DraftAction::Approve, input.actor.role) {
        return Err(AppError::Unauthorized);
    }
    // before_action: lock + status gate (Locks.lock_drafting_draft).
    if input.draft.status != DraftStatus::Drafting {
        return Err(AppError::DraftNotDrafting);
    }
    // validation: ValidatorPassed.
    validator_gate(input.draft.ai_validator_output.as_ref(), &input.draft.body)?;

    // compensation_body required (arg or existing), trimmed non-empty.
    let compensation_body = input
        .compensation_body_arg
        .or_else(|| input.draft.compensation_body.clone())
        .map(|b| b.trim().to_string())
        .filter(|b| !b.is_empty())
        .ok_or(AppError::CompensationBodyRequired)?;

    let action_create = ActionCreate {
        id: input.new_action_id,
        draft_id: input.draft.id,
        channel_id: input.channel_id,
        status: ActionStatus::Pending,
        outbound_idempotency_key: input.new_action_idempotency_key,
    };
    let compensation_create = CompensationCreate {
        id: input.new_compensation_id,
        action_id: input.new_action_id,
        body: compensation_body.clone(),
        status: CompStatus::Registered,
    };
    let draft_update = DraftApproveUpdate {
        status: DraftStatus::Approved,
        approved_at: input.now,
        approved_by_id: input.actor.id,
        compensation_body,
    };

    let chain_topic = input.draft.inbox_id.to_string();

    let mut draft_approved = Payload::new();
    draft_approved.insert("draft_id".into(), id(input.draft.id));
    draft_approved.insert("approved_at".into(), PayloadValue::DateTime(input.now));
    draft_approved.insert("approved_by_id".into(), id(input.actor.id));
    draft_approved.insert(
        "superseded_sibling_draft_ids".into(),
        PayloadValue::StrList(
            input
                .sibling_drafting_ids
                .iter()
                .map(|u| u.to_string())
                .collect(),
        ),
    );

    let mut comp_registered = Payload::new();
    comp_registered.insert("compensation_id".into(), id(input.new_compensation_id));
    comp_registered.insert("action_id".into(), id(input.new_action_id));

    let audit = chain(
        input.prev_audit_hash,
        vec![
            (EventType::DraftApproved, draft_approved),
            (EventType::CompensationRegistered, comp_registered),
        ],
    )?;

    Ok(ApprovePlan {
        chain_topic,
        draft_update,
        action_create,
        compensation_create,
        superseded_draft_ids: input.sibling_drafting_ids,
        audit,
    })
}

// ── Action.execute ───────────────────────────────────────────────────────

pub struct ExecuteInput {
    pub action_id: Uuid,
    pub draft_id: Uuid,
    pub channel_id: Uuid,
    pub action_status: ActionStatus,
    /// `draft.approved_at` — the countdown reference.
    pub draft_approved_at: Option<DateTime<Utc>>,
    pub inbox_id: Uuid,
    pub actor: Actor,
    pub now: DateTime<Utc>,
    pub prev_audit_hash: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExecutePlan {
    pub chain_topic: String,
    /// Action transitions to this status (`:scheduled`).
    pub action_status: ActionStatus,
    pub enqueue: JobEnqueue,
    pub audit: AuditAppend,
}

/// Plan `Action.execute`: from `:pending`, re-check the 5s countdown, flip to
/// `:scheduled`, enqueue the outbound send, emit `action_scheduled`.
pub fn plan_execute(input: ExecuteInput) -> Result<ExecutePlan, AppError> {
    if !resources::action::can("execute", input.actor.role) {
        return Err(AppError::Unauthorized);
    }
    // validate StatusTransition from [:pending].
    if input.action_status != ActionStatus::Pending {
        return Err(AppError::InvalidTransition);
    }
    // CountdownGuard against the draft's approved_at.
    if !countdown_ok(input.draft_approved_at, input.now) {
        return Err(AppError::CountdownViolation);
    }

    let mut payload = Payload::new();
    payload.insert("action_id".into(), id(input.action_id));
    payload.insert("draft_id".into(), id(input.draft_id));
    payload.insert("channel_id".into(), id(input.channel_id));
    let audit = chain(
        input.prev_audit_hash,
        vec![(EventType::ActionScheduled, payload)],
    )?
    .pop()
    .expect("one event");

    Ok(ExecutePlan {
        chain_topic: input.inbox_id.to_string(),
        action_status: ActionStatus::Scheduled,
        enqueue: JobEnqueue {
            queue: "outbound",
            args: serde_json::json!({ "action_id": input.action_id, "kind": "action" }),
            unique_key: awd_jobs::retry::outbound_unique_key(
                "action",
                &input.action_id.to_string(),
            ),
        },
        audit,
    })
}

// ── Compensation.initiate_trigger / trigger ────────────────────────────────

pub struct InitiateTriggerInput {
    pub compensation_status: CompStatus,
    pub actor: Actor,
    pub now: DateTime<Utc>,
    /// `"compensation-" + uuid`.
    pub new_idempotency_key: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct InitiateTriggerPlan {
    pub status: CompStatus,
    pub trigger_initiated_at: DateTime<Utc>,
    pub outbound_idempotency_key: String,
}

/// Plan `Compensation.initiate_trigger`: `:registered` → `:triggering`, stamping
/// the countdown reference + idempotency key. (No audit event — matches source.)
pub fn plan_initiate_trigger(input: InitiateTriggerInput) -> Result<InitiateTriggerPlan, AppError> {
    if !resources::compensation::can("initiate_trigger", input.actor.role) {
        return Err(AppError::Unauthorized);
    }
    if input.compensation_status != CompStatus::Registered {
        return Err(AppError::InvalidTransition);
    }
    Ok(InitiateTriggerPlan {
        status: CompStatus::Triggering,
        trigger_initiated_at: input.now,
        outbound_idempotency_key: input.new_idempotency_key,
    })
}

pub struct TriggerInput {
    pub compensation_id: Uuid,
    pub action_id: Uuid,
    pub compensation_status: CompStatus,
    /// The countdown reference stamped at initiate_trigger.
    pub trigger_initiated_at: Option<DateTime<Utc>>,
    pub inbox_id: Uuid,
    pub actor: Actor,
    pub now: DateTime<Utc>,
    pub prev_audit_hash: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TriggerPlan {
    pub chain_topic: String,
    pub status: CompStatus,
    pub enqueue: JobEnqueue,
    pub audit: AuditAppend,
}

/// Plan `Compensation.trigger`: from `:triggering`, re-check the 5s countdown
/// (against `trigger_initiated_at`), flip to `:scheduled`, enqueue, emit
/// `compensation_scheduled`.
pub fn plan_trigger(input: TriggerInput) -> Result<TriggerPlan, AppError> {
    if !resources::compensation::can("trigger", input.actor.role) {
        return Err(AppError::Unauthorized);
    }
    if input.compensation_status != CompStatus::Triggering {
        return Err(AppError::InvalidTransition);
    }
    if !countdown_ok(input.trigger_initiated_at, input.now) {
        return Err(AppError::CountdownViolation);
    }

    let mut payload = Payload::new();
    payload.insert("compensation_id".into(), id(input.compensation_id));
    payload.insert("action_id".into(), id(input.action_id));
    let audit = chain(
        input.prev_audit_hash,
        vec![(EventType::CompensationScheduled, payload)],
    )?
    .pop()
    .expect("one event");

    Ok(TriggerPlan {
        chain_topic: input.inbox_id.to_string(),
        status: CompStatus::Scheduled,
        enqueue: JobEnqueue {
            queue: "outbound",
            args: serde_json::json!({ "compensation_id": input.compensation_id, "kind": "compensation" }),
            unique_key: awd_jobs::retry::outbound_unique_key(
                "compensation",
                &input.compensation_id.to_string(),
            ),
        },
        audit,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use awd_domain::audit::{verify_chain, ChainEvent, WalkResult};

    fn uuid(n: u128) -> Uuid {
        Uuid::from_u128(n)
    }

    fn operator() -> Actor {
        Actor {
            id: uuid(0xA),
            role: Role::Operator,
        }
    }

    fn t(secs: i64) -> DateTime<Utc> {
        DateTime::from_timestamp(1_700_000_000 + secs, 0).unwrap()
    }

    fn approve_input(validator: Option<Value>, comp_body: Option<&str>) -> ApproveInput {
        ApproveInput {
            draft: DraftState {
                id: uuid(1),
                inbox_id: uuid(2),
                status: DraftStatus::Drafting,
                body: "Thanks, see you then.".into(),
                compensation_body: None,
                ai_validator_output: validator,
            },
            actor: operator(),
            now: t(0),
            compensation_body_arg: comp_body.map(str::to_string),
            channel_id: uuid(3),
            new_action_id: uuid(4),
            new_compensation_id: uuid(5),
            new_action_idempotency_key: "action-aaaa".into(),
            sibling_drafting_ids: vec![uuid(6), uuid(7)],
            prev_audit_hash: None,
        }
    }

    #[test]
    fn approve_happy_path_produces_paired_chain() {
        let plan = plan_approve(approve_input(
            Some(serde_json::json!({"passed?": true})),
            Some("On our way."),
        ))
        .unwrap();

        assert_eq!(plan.draft_update.status, DraftStatus::Approved);
        assert_eq!(plan.draft_update.compensation_body, "On our way.");
        assert_eq!(plan.action_create.status, ActionStatus::Pending);
        assert!(plan
            .action_create
            .outbound_idempotency_key
            .starts_with("action-"));
        assert_eq!(plan.compensation_create.status, CompStatus::Registered);
        assert_eq!(plan.compensation_create.action_id, plan.action_create.id);
        assert_eq!(plan.superseded_draft_ids, vec![uuid(6), uuid(7)]);

        // Two events, in order, forming a valid chain off the empty prev.
        assert_eq!(plan.audit.len(), 2);
        assert_eq!(plan.audit[0].event_type, EventType::DraftApproved);
        assert_eq!(plan.audit[1].event_type, EventType::CompensationRegistered);
        assert_eq!(
            plan.audit[1].prev_hash.as_deref(),
            Some(plan.audit[0].hash.as_str())
        );
        let events: Vec<ChainEvent> = plan
            .audit
            .iter()
            .map(|a| ChainEvent {
                event_type: a.event_type,
                payload: &a.payload,
                stored_hash: &a.hash,
            })
            .collect();
        assert_eq!(verify_chain(&events), WalkResult::Ok { length: 2 });
    }

    #[test]
    fn approve_falls_back_to_draft_compensation_body() {
        let mut input = approve_input(Some(serde_json::json!({"passed?": true})), None);
        input.draft.compensation_body = Some("  draft-level body  ".into());
        let plan = plan_approve(input).unwrap();
        assert_eq!(plan.draft_update.compensation_body, "draft-level body"); // trimmed
    }

    #[test]
    fn approve_requires_compensation_body() {
        let err = plan_approve(approve_input(
            Some(serde_json::json!({"passed?": true})),
            Some("  "),
        ))
        .unwrap_err();
        assert_eq!(err, AppError::CompensationBodyRequired);
    }

    #[test]
    fn approve_validator_gate() {
        // AI says not passed → blocked.
        assert_eq!(
            plan_approve(approve_input(
                Some(serde_json::json!({"passed?": false})),
                Some("x")
            ))
            .unwrap_err(),
            AppError::ValidatorNotPassed
        );
        // No AI output, clean body → manual path ok.
        assert!(plan_approve(approve_input(None, Some("x"))).is_ok());
        // No AI output, body trips honest framing → blocked.
        let mut bad = approve_input(None, Some("x"));
        bad.draft.body = "You can unsend this later".into();
        assert_eq!(
            plan_approve(bad).unwrap_err(),
            AppError::HonestFramingFailed
        );
    }

    #[test]
    fn approve_rejects_non_drafting_and_unauthorized() {
        let mut not_drafting = approve_input(Some(serde_json::json!({"passed?": true})), Some("x"));
        not_drafting.draft.status = DraftStatus::Approved;
        assert_eq!(
            plan_approve(not_drafting).unwrap_err(),
            AppError::DraftNotDrafting
        );

        let mut viewer = approve_input(Some(serde_json::json!({"passed?": true})), Some("x"));
        viewer.actor.role = Role::Viewer;
        assert_eq!(plan_approve(viewer).unwrap_err(), AppError::Unauthorized);
    }

    fn execute_input(
        status: ActionStatus,
        approved_at: Option<DateTime<Utc>>,
        now: DateTime<Utc>,
    ) -> ExecuteInput {
        ExecuteInput {
            action_id: uuid(4),
            draft_id: uuid(1),
            channel_id: uuid(3),
            action_status: status,
            draft_approved_at: approved_at,
            inbox_id: uuid(2),
            actor: operator(),
            now,
            prev_audit_hash: Some("a".repeat(64)),
        }
    }

    #[test]
    fn execute_enforces_countdown() {
        // 3s elapsed → violation.
        assert_eq!(
            plan_execute(execute_input(ActionStatus::Pending, Some(t(0)), t(3))).unwrap_err(),
            AppError::CountdownViolation
        );
        // 5s elapsed → ok.
        let plan = plan_execute(execute_input(ActionStatus::Pending, Some(t(0)), t(5))).unwrap();
        assert_eq!(plan.action_status, ActionStatus::Scheduled);
        assert_eq!(plan.enqueue.queue, "outbound");
        assert_eq!(
            plan.enqueue.unique_key,
            "outbound:00000000-0000-0000-0000-000000000004:action"
        );
        assert_eq!(plan.audit.event_type, EventType::ActionScheduled);
        assert_eq!(
            plan.audit.prev_hash.as_deref(),
            Some("a".repeat(64).as_str())
        );
    }

    #[test]
    fn execute_rejects_wrong_status_and_missing_approved_at() {
        assert_eq!(
            plan_execute(execute_input(ActionStatus::Scheduled, Some(t(0)), t(10))).unwrap_err(),
            AppError::InvalidTransition
        );
        assert_eq!(
            plan_execute(execute_input(ActionStatus::Pending, None, t(10))).unwrap_err(),
            AppError::CountdownViolation
        );
    }

    #[test]
    fn initiate_trigger_stamps_reference_and_key() {
        let plan = plan_initiate_trigger(InitiateTriggerInput {
            compensation_status: CompStatus::Registered,
            actor: operator(),
            now: t(0),
            new_idempotency_key: "compensation-bbbb".into(),
        })
        .unwrap();
        assert_eq!(plan.status, CompStatus::Triggering);
        assert_eq!(plan.trigger_initiated_at, t(0));
        assert!(plan.outbound_idempotency_key.starts_with("compensation-"));
    }

    #[test]
    fn trigger_enforces_countdown_and_emits_event() {
        let mk = |status, ts, now| TriggerInput {
            compensation_id: uuid(5),
            action_id: uuid(4),
            compensation_status: status,
            trigger_initiated_at: ts,
            inbox_id: uuid(2),
            actor: operator(),
            now,
            prev_audit_hash: None,
        };
        // not yet 5s
        assert_eq!(
            plan_trigger(mk(CompStatus::Triggering, Some(t(0)), t(4))).unwrap_err(),
            AppError::CountdownViolation
        );
        // wrong status
        assert_eq!(
            plan_trigger(mk(CompStatus::Registered, Some(t(0)), t(10))).unwrap_err(),
            AppError::InvalidTransition
        );
        // ok
        let plan = plan_trigger(mk(CompStatus::Triggering, Some(t(0)), t(5))).unwrap();
        assert_eq!(plan.status, CompStatus::Scheduled);
        assert_eq!(plan.audit.event_type, EventType::CompensationScheduled);
        assert_eq!(
            plan.enqueue.unique_key,
            "outbound:00000000-0000-0000-0000-000000000005:compensation"
        );
    }
}
