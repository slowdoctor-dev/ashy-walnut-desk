defmodule AshyWalnutDesk.Interaction.AuditChain do
  @moduledoc false

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.AuditEvent
  alias AshyWalnutDesk.Repo

  @payload_allowlist %{
    inbox_opened: [:inbox_id, :conversation_id, :identity_id],
    draft_started: [:inbox_id, :draft_id],
    draft_approved: [:draft_id, :approved_at, :approved_by_id],
    action_scheduled: [:action_id, :draft_id, :channel_id],
    action_executed: [:action_id, :draft_id, :channel_id, :outcome],
    compensation_registered: [:compensation_id, :action_id],
    compensation_scheduled: [:compensation_id, :action_id],
    compensation_executed: [:compensation_id, :action_id, :outcome]
  }

  def canonicalize_payload(event_type, payload) when is_map(payload) do
    with {:ok, allowed_keys} <- Map.fetch(@payload_allowlist, event_type),
         :ok <- reject_unknown_keys(payload, allowed_keys) do
      canonical =
        allowed_keys
        |> Enum.reduce(%{}, fn key, acc ->
          value = Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
          Map.put(acc, Atom.to_string(key), canonical_value(value))
        end)

      {:ok, canonical}
    else
      :error -> {:error, {:unknown_event_type, event_type}}
      {:error, reason} -> {:error, reason}
    end
  end

  def canonicalize_payload(event_type, _payload),
    do: {:error, {:invalid_payload_type, event_type}}

  def compute_hash(prev_hash, canonical_json) when is_binary(canonical_json) do
    prefix = prev_hash || ""
    :crypto.hash(:sha256, prefix <> canonical_json) |> Base.encode16(case: :lower)
  end

  def walk(chain_topic) do
    walk_events(load_events(chain_topic))
  end

  @doc """
  Per-event hash-continuity check for the admin LV viewer (story 3.7).

  Returns a list of `{event, status}` tuples where `status` is
  `:ok` (computed hash matches the stored hash AND chains from the
  prior event's hash), or `:broken` (mismatch — corresponds to the
  same condition `mix audit.verify` exits non-zero on).

  Unlike `walk/1`, this never halts: the LV needs to show subsequent
  rows after a broken one with a "broken upstream" badge.
  """
  def walk_with_status(chain_topic) do
    chain_topic
    |> load_events()
    |> Enum.map_reduce({:ok, nil}, fn event, {chain_state, prev_hash} ->
      status = continuity_status(event, prev_hash, chain_state)
      next_state = {if(status == :ok, do: :ok, else: :broken), event.hash}
      {{event, status}, next_state}
    end)
    |> elem(0)
  end

  defp continuity_status(_event, _prev_hash, :broken), do: :broken

  defp continuity_status(event, prev_hash, :ok) do
    with {:ok, canonical} <- canonicalize_payload(event.event_type, event.payload),
         {:ok, json} <- Jason.encode(canonical),
         computed <- compute_hash(prev_hash, json),
         true <- computed == event.hash do
      :ok
    else
      _ -> :broken
    end
  end

  defp load_events(chain_topic) do
    AuditEvent
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(expr(chain_topic == ^chain_topic))
    |> Ash.Query.sort([{:inserted_at, :asc}, {:id, :asc}])
    |> Ash.read!(authorize?: false)
  end

  @doc """
  Returns the most recently active chain topics, capped at the
  configured limit (default 200) and ordered by latest event first.

  Story 3.fix:
  - Bounded result set so the admin LV doesn't try to render every
    historical topic.
  - DB errors are logged (not swallowed) and re-raised so the LV's
    error boundary surfaces them instead of pretending the system
    has no chains.
  """
  def all_chain_topics(opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    sql = """
    SELECT chain_topic
    FROM audit_events
    WHERE chain_topic IS NOT NULL
    GROUP BY chain_topic
    ORDER BY MAX(inserted_at) DESC
    LIMIT $1
    """

    case Repo.query(sql, [limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [topic] -> topic end)

      {:error, error} ->
        require Logger
        Logger.error("AuditChain.all_chain_topics failed: #{inspect(error)}")
        raise error
    end
  end

  defp walk_events(events) do
    events
    |> Enum.reduce_while({:ok, nil, []}, fn event, {:ok, prev_hash, acc} ->
      with {:ok, canonical} <- canonicalize_payload(event.event_type, event.payload),
           {:ok, canonical_json} <- Jason.encode(canonical),
           computed <- compute_hash(prev_hash, canonical_json),
           true <- computed == event.hash do
        {:cont, {:ok, event.hash, [event | acc]}}
      else
        _ -> {:halt, {:error, {:broken_at, event.id}}}
      end
    end)
    |> case do
      {:ok, _prev, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  defp reject_unknown_keys(payload, allowed_keys) do
    allowed_string_keys = MapSet.new(Enum.map(allowed_keys, &Atom.to_string/1))
    allowed_atom_keys = MapSet.new(allowed_keys)

    payload
    |> Map.keys()
    |> Enum.find(fn key ->
      case key do
        atom when is_atom(atom) -> not MapSet.member?(allowed_atom_keys, atom)
        bin when is_binary(bin) -> not MapSet.member?(allowed_string_keys, bin)
        _ -> true
      end
    end)
    |> case do
      nil -> :ok
      key -> {:error, {:invalid_payload_key, key}}
    end
  end

  defp canonical_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp canonical_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp canonical_value(value) when is_atom(value), do: Atom.to_string(value)
  defp canonical_value(value), do: value
end
