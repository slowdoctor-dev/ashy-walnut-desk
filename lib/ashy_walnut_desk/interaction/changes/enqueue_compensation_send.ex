defmodule AshyWalnutDesk.Interaction.Changes.EnqueueCompensationSend do
  @moduledoc """
  Compensation analog of `EnqueueOutboundSend`. Runs in the operator's
  `Compensation.:trigger` transaction after `CompensationCountdownGuard`
  has validated the 5-second window. Inserts a `Jobs.OutboundSend`
  Oban job with `kind: "compensation"` so the worker dispatches to
  the compensation branch of `perform/1`.

  Same uniqueness window as `EnqueueOutboundSend` (60 seconds, keyed
  on `(compensation_id, kind)`) so a double-click within the window
  produces at most one outbound HTTP call.

  See ADR-023 and `specs/phase-3/architecture.md §3.4, §6.3`.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.Jobs.OutboundSend

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, &enqueue/2)
  end

  defp enqueue(_changeset, compensation) do
    args = %{"compensation_id" => compensation.id, "kind" => "compensation"}

    case args
         |> OutboundSend.new(unique: [period: 60, keys: [:compensation_id, :kind]])
         |> Oban.insert() do
      {:ok, _job} -> {:ok, compensation}
      {:error, reason} -> {:error, reason}
    end
  end
end
