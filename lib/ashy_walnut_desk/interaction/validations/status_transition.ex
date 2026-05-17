defmodule AshyWalnutDesk.Interaction.Validations.StatusTransition do
  @moduledoc """
  Validates that the current record's status is in the configured
  `:from` list before allowing the transition. Used by per-
  transition update actions on `Inbox` (and any future resource
  with an explicit state machine) so the state-machine integrity
  doesn't depend on which `accept` list happened to include `:status`.

      validate {StatusTransition, from: [:open, :drafting]}
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(%Changeset{} = changeset, opts, _context) do
    from = opts |> Keyword.fetch!(:from) |> List.wrap()
    current = changeset.data.status

    if current in from do
      :ok
    else
      {:error,
       field: :status,
       message: "invalid transition from #{inspect(current)} (allowed: #{inspect(from)})"}
    end
  end
end
