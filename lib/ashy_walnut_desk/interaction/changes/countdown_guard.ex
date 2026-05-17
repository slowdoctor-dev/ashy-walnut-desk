defmodule AshyWalnutDesk.Interaction.Changes.CountdownGuard do
  @moduledoc """
  Pre-action guard on `Action.:execute`. Loads the related draft and
  verifies that at least 5 seconds (ADR-013) have elapsed since
  `approved_at`. On violation, adds an error to the changeset so the
  update fails before the adapter is invoked.

  Side effect: stashes the loaded `%Draft{}` (with inbox preloaded)
  into the changeset context under `:draft` so `ExecuteOutbound`
  doesn't have to re-query.

  This change is intentionally narrow: no adapter call, no Message
  creation, no Inbox transition. Those belong to `ExecuteOutbound`.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Interaction.{Draft, ErrorHelpers}

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
    with {:ok, draft} <- load_draft_with_inbox(changeset.data.draft_id),
         :ok <- countdown_ok?(draft) do
      Changeset.set_context(changeset, %{draft: draft})
    else
      {:error, :countdown_violation} ->
        Changeset.add_error(changeset, field: :draft_id, message: "countdown_violation")

      {:error, reason} ->
        Changeset.add_error(changeset, field: :draft_id, message: error_text(reason))
    end
  end

  defp countdown_ok?(%Draft{approved_at: nil}), do: {:error, :countdown_violation}

  defp countdown_ok?(%Draft{approved_at: approved_at}) do
    if DateTime.diff(DateTime.utc_now(), approved_at, :second) >= @countdown_seconds do
      :ok
    else
      {:error, :countdown_violation}
    end
  end

  defp load_draft_with_inbox(draft_id) do
    case Ash.get(Draft, draft_id, authorize?: false) do
      {:ok, draft} -> {:ok, Ash.load!(draft, [:inbox], authorize?: false)}
      {:error, error} -> {:error, error}
    end
  end

  defp error_text(error), do: ErrorHelpers.error_to_string(error)
end
