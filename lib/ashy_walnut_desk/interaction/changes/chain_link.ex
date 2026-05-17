defmodule AshyWalnutDesk.Interaction.Changes.ChainLink do
  @moduledoc false

  use Ash.Resource.Change

  import Ash.Expr
  require Ash.Query

  alias Ash.Changeset

  alias AshyWalnutDesk.Interaction.{
    Action,
    AuditChain,
    AuditEvent,
    Compensation,
    Conversation,
    Draft,
    Inbox
  }

  alias AshyWalnutDesk.Repo

  @impl true
  def change(changeset, opts, _context) do
    event_type = Keyword.fetch!(opts, :event_type)

    Changeset.after_action(changeset, fn changeset, record ->
      write_events(changeset, record, event_type)
    end)
  end

  defp write_events(changeset, record, event_type) do
    with {:ok, chain_topic} <- chain_topic_for(record),
         {:ok, events} <- event_specs(changeset, record, event_type),
         :ok <- write_event_rows(chain_topic, events) do
      {:ok, record}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_event_rows(chain_topic, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      with {:ok, prev_hash} <- lock_prev_hash(chain_topic),
           payload = maybe_normalize_outcome(event.payload),
           {:ok, canonical} <- AuditChain.canonicalize_payload(event.event_type, payload),
           {:ok, canonical_json} <- Jason.encode(canonical),
           hash <- AuditChain.compute_hash(prev_hash, canonical_json),
           {:ok, _audit_event} <-
             create_audit_event(chain_topic, event, payload, prev_hash, hash) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp lock_prev_hash(chain_topic) do
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
      {:error, error} -> {:error, error}
    end
  end

  defp create_audit_event(chain_topic, event, payload, prev_hash, hash) do
    Ash.create(
      AuditEvent,
      %{
        chain_topic: chain_topic,
        event_type: event.event_type,
        subject_kind: event.subject_kind,
        subject_id: event.subject_id,
        payload: stringify_keys(payload),
        prev_hash: prev_hash,
        hash: hash,
        actor_id: event.actor_id
      },
      action: :create,
      authorize?: false
    )
  end

  defp event_specs(_changeset, %Inbox{} = inbox, :inbox_opened) do
    with {:ok, conversation} <- Ash.get(Conversation, inbox.conversation_id, authorize?: false) do
      {:ok,
       [
         %{
           event_type: :inbox_opened,
           subject_kind: :inbox,
           subject_id: inbox.id,
           actor_id: inbox.recorded_by_id,
           payload: %{
             inbox_id: inbox.id,
             conversation_id: inbox.conversation_id,
             identity_id: conversation.identity_id
           }
         }
       ]}
    end
  end

  defp event_specs(_changeset, %Draft{} = draft, :draft_started) do
    {:ok,
     [
       %{
         event_type: :draft_started,
         subject_kind: :draft,
         subject_id: draft.id,
         actor_id: draft.approved_by_id,
         payload: %{inbox_id: draft.inbox_id, draft_id: draft.id}
       }
     ]}
  end

  defp event_specs(_changeset, %Draft{} = draft, :draft_approved) do
    with {:ok, action} <- action_for_draft(draft.id),
         {:ok, compensation} <- compensation_for_action(action.id) do
      {:ok,
       [
         %{
           event_type: :draft_approved,
           subject_kind: :draft,
           subject_id: draft.id,
           actor_id: draft.approved_by_id,
           payload: %{
             draft_id: draft.id,
             approved_at: draft.approved_at,
             approved_by_id: draft.approved_by_id
           }
         },
         %{
           event_type: :compensation_registered,
           subject_kind: :compensation,
           subject_id: compensation.id,
           actor_id: draft.approved_by_id,
           payload: %{compensation_id: compensation.id, action_id: action.id}
         }
       ]}
    end
  end

  defp event_specs(_changeset, %Action{} = action, :action_executed) do
    {:ok,
     [
       %{
         event_type: :action_executed,
         subject_kind: :action,
         subject_id: action.id,
         actor_id: nil,
         payload: %{
           action_id: action.id,
           draft_id: action.draft_id,
           channel_id: action.channel_id,
           outcome: action.status
         }
       }
     ]}
  end

  defp event_specs(_changeset, _record, event_type),
    do: {:error, {:unsupported_chain_event, event_type}}

  defp chain_topic_for(%Inbox{id: inbox_id}), do: {:ok, to_string(inbox_id)}

  defp chain_topic_for(%Draft{inbox_id: inbox_id}) when not is_nil(inbox_id),
    do: {:ok, to_string(inbox_id)}

  defp chain_topic_for(%Draft{id: draft_id}) do
    with {:ok, draft} <- Ash.get(Draft, draft_id, authorize?: false) do
      {:ok, to_string(draft.inbox_id)}
    end
  end

  defp chain_topic_for(%Action{draft_id: draft_id}) do
    with {:ok, draft} <- Ash.get(Draft, draft_id, authorize?: false) do
      {:ok, to_string(draft.inbox_id)}
    end
  end

  defp action_for_draft(draft_id) do
    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^draft_id))
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.read_one(authorize?: false)

    case action do
      {:ok, nil} -> {:error, :action_not_found}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end

  defp compensation_for_action(action_id) do
    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^action_id))
      |> Ash.read_one(authorize?: false)

    case compensation do
      {:ok, nil} -> {:error, :compensation_not_found}
      {:ok, record} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_outcome(:executed), do: :executed
  defp normalize_outcome(:failed), do: :failed
  defp normalize_outcome(other), do: other

  defp maybe_normalize_outcome(payload) do
    case Map.fetch(payload, :outcome) do
      {:ok, outcome} -> Map.put(payload, :outcome, normalize_outcome(outcome))
      :error -> payload
    end
  end
end
