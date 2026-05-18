defmodule AshyWalnutDesk.Interaction.Changes.CompensationCountdownGuard do
  @moduledoc """
  Compensation analog of `CountdownGuard`. Verifies at least 5
  seconds (ADR-013, AGENTS.md §7.2) have elapsed between
  `:initiate_trigger` (which stamps `trigger_initiated_at`) and the
  follow-up `:trigger` call.

  On violation: adds an error to the changeset so the update fails
  before the Oban job is enqueued.

  Mirrors the Phase 2 `CountdownGuard` rule. Same 5-second window;
  no carve-out for compensation per the story 3.6 acceptance criteria.
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @countdown_seconds 5

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      if Enum.any?(changeset.errors) do
        changeset
      else
        guard(changeset)
      end
    end)
  end

  defp guard(changeset) do
    case countdown_ok?(changeset.data) do
      :ok ->
        changeset

      {:error, :countdown_violation} ->
        Changeset.add_error(changeset,
          field: :trigger_initiated_at,
          message: "countdown_violation"
        )
    end
  end

  defp countdown_ok?(%{trigger_initiated_at: nil}), do: {:error, :countdown_violation}

  defp countdown_ok?(%{trigger_initiated_at: ts}) do
    if DateTime.diff(DateTime.utc_now(), ts, :second) >= @countdown_seconds do
      :ok
    else
      {:error, :countdown_violation}
    end
  end
end
