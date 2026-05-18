defmodule AshyWalnutDesk.Interaction.Changes.EnqueueOutboundSend do
  @moduledoc """
  After `CountdownGuard` has validated the 5-second send window,
  transition the `Action` from `:pending` to `:scheduled` and enqueue
  the `Jobs.OutboundSend` Oban worker that performs the real
  adapter call.

  Per ADR-023, the LV transaction does NOT block on the network call.
  This change runs inside the operator's `Action.:execute` transaction:

  1. `before_action` flips `status: :scheduled` so the chain row is
     in a deterministic intermediate state for any LV/PubSub
     subscriber that re-renders before the worker fires.
  2. `after_action` calls `Oban.insert!/1` with a uniqueness window
     so an operator double-click within 60 seconds enqueues at most
     one outbound job for the action.

  The worker then drives `Action.:complete_outbound` or
  `Action.:fail_outbound` per the adapter result.

  See `specs/phase-3/architecture.md §6.1` (outbound flow).
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.Jobs.OutboundSend

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(&schedule/1)
    |> Changeset.after_action(&enqueue/2)
  end

  defp schedule(changeset) do
    if Enum.any?(changeset.errors) do
      changeset
    else
      Changeset.force_change_attribute(changeset, :status, :scheduled)
    end
  end

  defp enqueue(_changeset, action) do
    args = %{"action_id" => action.id, "kind" => "action"}

    case OutboundSend.new(args, unique: [period: 60, keys: [:action_id, :kind]])
         |> Oban.insert() do
      {:ok, _job} -> {:ok, action}
      {:error, reason} -> {:error, reason}
    end
  end
end
