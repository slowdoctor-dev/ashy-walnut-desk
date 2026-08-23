//! # awd-jobs
//!
//! The Postgres-backed durable job queue (Oban/ash_oban replacement). The
//! queue table, transactional enqueue, and `SELECT … FOR UPDATE SKIP LOCKED`
//! claiming need SQLx + Postgres and are deferred. Implemented and tested here
//! is the **pure retry envelope**:
//!
//! - [`backoff`] — the exact per-worker backoff schedules + max-attempt counts
//!   (`outbound_send.ex`, `generation_worker.ex`).
//! - [`retry`] — the job state enum + the retry-vs-exhausted decision.

pub mod backoff;
pub mod retry;

pub use awd_domain;
