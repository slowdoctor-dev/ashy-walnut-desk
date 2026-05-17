defmodule AshyWalnutDesk.Interaction.Validations.NotApprovingViaRevise do
  @moduledoc """
  Rejects an attempt to set `status: :approved` via `Draft.:revise`.
  Approving must go through `Draft.:approve`, which fires
  `CompensationAtApproval` to create the matching `Action` +
  `Compensation` rows. A bare `Ash.update(draft, %{status: :approved},
  action: :revise)` would otherwise mark the draft `:approved`
  without the four-stage chain ever firing — a data-integrity drift,
  not a security finding (Action.:execute can't run without an
  Action row), but the inconsistent state would confuse any chain
  inspector. See S5 in the simplicity review.

  Other `:status` transitions via `:revise` (e.g. `:rejected`,
  `:superseded`) are still allowed.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(%Changeset{} = changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :status) do
      :approved ->
        {:error, field: :status, message: "use the :approve action to approve a draft"}

      _ ->
        :ok
    end
  end
end
