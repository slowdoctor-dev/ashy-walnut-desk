defmodule AshyWalnutDesk.Interaction.Locks do
  @moduledoc """
  Tiny named API for the two raw-SQL `FOR UPDATE` escape hatches the
  Interaction axis needs to defend its concurrency invariants. Today
  AshPostgres doesn't expose pessimistic locking through the Ash
  read pipeline (TO-7), so the two callsites have to hand-roll
  `Repo.query/2` + `Ecto.UUID.dump!/1` themselves.

  Consolidating behind this module:
  - Pins the raw-SQL surface to two named functions instead of two
    scattered query strings, so a future Ash-native replacement (or
    AshPostgres adding `lock_for_update`) is a single-file change.
  - Stops accidental divergence on result-shape pattern matching.
  - Documents the locking semantics in one place.

  See A3 in the simplicity review. TO-7 stays open until AshPostgres
  ships first-class pessimistic locking; this is just a tidier
  workaround.
  """

  alias AshyWalnutDesk.Repo

  @doc """
  Acquire a row-level FOR UPDATE lock on the `drafts` row identified
  by `draft_id`, filtered to `status = 'drafting'`. Returns:

  - `{:ok, :locked}` when the lock was acquired (status matched).
  - `{:ok, :not_drafting}` when the row exists but is in a different
    status (e.g. already approved by a concurrent caller).
  - `{:error, reason}` on any database error.

  Must be called inside an Ecto transaction or Ash action with
  transactional semantics; without one, the lock is released
  immediately.
  """
  @spec lock_drafting_draft(Ecto.UUID.t()) ::
          {:ok, :locked} | {:ok, :not_drafting} | {:error, term()}
  def lock_drafting_draft(draft_id) do
    draft_id_bin = Ecto.UUID.dump!(draft_id)

    case Repo.query(
           "SELECT id FROM drafts WHERE id = $1 AND status = 'drafting' FOR UPDATE",
           [draft_id_bin]
         ) do
      {:ok, %{num_rows: 1}} -> {:ok, :locked}
      {:ok, %{num_rows: 0}} -> {:ok, :not_drafting}
      {:error, _} = error -> error
    end
  end

  @doc """
  Resolve the channel_id for a draft by walking
  `drafts → inboxes → conversations`. Used by
  `CompensationAtApproval` to know which channel the approved draft
  is bound to (the `Conversation.channel_id` is authoritative).

  Returns `{:ok, channel_id_uuid}`, `{:ok, :not_found}`, or
  `{:error, reason}`.
  """
  @spec resolve_channel_for_draft(Ecto.UUID.t()) ::
          {:ok, Ecto.UUID.t()} | {:ok, :not_found} | {:error, term()}
  def resolve_channel_for_draft(draft_id) do
    draft_id_bin = Ecto.UUID.dump!(draft_id)

    case Repo.query(
           """
           SELECT c.channel_id
           FROM drafts d
           JOIN inboxes i ON i.id = d.inbox_id
           JOIN conversations c ON c.id = i.conversation_id
           WHERE d.id = $1
           """,
           [draft_id_bin]
         ) do
      {:ok, %{rows: [[channel_id]]}} -> {:ok, channel_id}
      {:ok, %{rows: []}} -> {:ok, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Acquire a FOR UPDATE lock on the most-recent audit_events row for
  the given `chain_topic`, returning the hash of that row (or `nil`
  if no rows exist yet). Used by `ChainLink` to serialize hash-chain
  writes against concurrent approvers operating on the same inbox.
  """
  @spec lock_prev_audit_hash(String.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def lock_prev_audit_hash(chain_topic) when is_binary(chain_topic) do
    sql = """
    SELECT hash
    FROM audit_events
    WHERE chain_topic = $1
    ORDER BY inserted_at DESC, id DESC
    LIMIT 1
    FOR UPDATE
    """

    case Repo.query(sql, [chain_topic]) do
      {:ok, %{rows: []}} -> {:ok, nil}
      {:ok, %{rows: [[prev_hash]]}} -> {:ok, prev_hash}
      {:error, _} = error -> error
    end
  end
end
