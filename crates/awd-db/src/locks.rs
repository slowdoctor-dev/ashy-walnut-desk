//! The pessimistic `FOR UPDATE` locks — port of `interaction/locks.ex`.
//!
//! AshPostgres didn't expose pessimistic locking through its read pipeline, so
//! these were hand-rolled raw SQL in Elixir; they translate 1:1 to SQLx
//! `query`/`query_as` against a `&mut Transaction`. The SQL is pinned here as
//! constants so the (later) execution layer and tests share one source of
//! truth. Each must run inside a transaction or the lock releases immediately.

/// Lock the `drafts` row by id, only if `status = 'drafting'`. 1 row → locked;
/// 0 rows → not_drafting (or absent); used by the approve flow.
pub const LOCK_DRAFTING_DRAFT: &str =
    "SELECT id FROM drafts WHERE id = $1 AND status = 'drafting' FOR UPDATE";

/// Resolve the authoritative channel for a draft via
/// `drafts → inboxes → conversations` (the `Conversation.channel_id`).
pub const RESOLVE_CHANNEL_FOR_DRAFT: &str = "\
SELECT c.channel_id
FROM drafts d
JOIN inboxes i ON i.id = d.inbox_id
JOIN conversations c ON c.id = i.conversation_id
WHERE d.id = $1";

/// Lock the most-recent `audit_events` row for a `chain_topic` and return its
/// hash (or none). Serializes hash-chain appends against concurrent approvers
/// on the same inbox. Ordering MUST match the verifier: inserted_at DESC, id DESC.
pub const LOCK_PREV_AUDIT_HASH: &str = "\
SELECT hash
FROM audit_events
WHERE chain_topic = $1
ORDER BY inserted_at DESC, id DESC
LIMIT 1
FOR UPDATE";

/// Result of [`LOCK_DRAFTING_DRAFT`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DraftLock {
    Locked,
    NotDrafting,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locks_use_for_update() {
        assert!(LOCK_DRAFTING_DRAFT.contains("FOR UPDATE"));
        assert!(LOCK_PREV_AUDIT_HASH.contains("FOR UPDATE"));
    }

    #[test]
    fn prev_hash_ordering_matches_verifier() {
        // The chain walker orders (inserted_at ASC, id ASC); the lock takes the
        // tip via DESC,DESC + LIMIT 1. These must agree on the tie-break column.
        assert!(LOCK_PREV_AUDIT_HASH.contains("ORDER BY inserted_at DESC, id DESC"));
        assert!(LOCK_PREV_AUDIT_HASH.contains("LIMIT 1"));
    }

    #[test]
    fn channel_resolution_walks_three_tables() {
        assert!(RESOLVE_CHANNEL_FOR_DRAFT.contains("JOIN inboxes"));
        assert!(RESOLVE_CHANNEL_FOR_DRAFT.contains("JOIN conversations"));
    }
}
