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
    compensation_registered: [:compensation_id, :action_id]
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
    events =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(chain_topic == ^chain_topic))
      |> Ash.Query.sort([{:inserted_at, :asc}, {:id, :asc}])
      |> Ash.read!(authorize?: false)

    walk_events(events)
  end

  def all_chain_topics do
    case Repo.query(
           "SELECT DISTINCT chain_topic FROM audit_events WHERE chain_topic IS NOT NULL",
           []
         ) do
      {:ok, %{rows: rows}} -> Enum.map(rows, fn [topic] -> topic end)
      {:error, _error} -> []
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
