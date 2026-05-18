defmodule AshyWalnutDesk.Interaction.Changes.RecordOutbound do
  @moduledoc """
  Persistence side of the outbound flow: after the worker has stamped
  the adapter response on the Action and transitioned status to
  `:executed`, write the outbound `Message` row and transition the
  Inbox to `:executed`.

  Runs inside the `Action.:complete_outbound` action, so the policy
  gate (`FromActionWorker`) already guarantees this code only runs
  from the Oban worker process. Uses internal-context flags
  (`from_action_execute: true`) to bypass the operator-only
  restrictions on `Message.:record_message` (outbound direction) and
  `Inbox.:mark_executed`.

  Originally inlined in `Changes.ExecuteOutbound` (Phase 2); split out
  in story 3.5 so the LV-side `:execute` and worker-side
  `:complete_outbound` can stay distinct transactions per ADR-023.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Draft, Message}

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, &persist_outbound/2)
  end

  defp persist_outbound(_changeset, %{status: :executed} = action) do
    with {:ok, draft} <- load_draft(action.draft_id),
         {:ok, _message} <- create_outbound_message(action, draft, action.executed_at),
         {:ok, _inbox} <- mark_inbox_executed(draft.inbox) do
      {:ok, action}
    end
  end

  defp persist_outbound(_changeset, action), do: {:ok, action}

  defp load_draft(draft_id) do
    Ash.get(Draft, draft_id, load: [:inbox], authorize?: false)
  end

  defp create_outbound_message(action, draft, sent_at) do
    Ash.create(
      Message,
      %{
        conversation_id: draft.inbox.conversation_id,
        direction: :outbound,
        body: draft.body,
        sent_at: sent_at,
        approved_by_id: draft.approved_by_id,
        outbound_idempotency_key: action.outbound_idempotency_key
      },
      action: :record_message,
      authorize?: false,
      context: %{from_action_execute: true}
    )
  end

  defp mark_inbox_executed(inbox) do
    Ash.update(
      inbox,
      %{},
      action: :mark_executed,
      authorize?: false,
      context: %{from_action_execute: true}
    )
  end
end
