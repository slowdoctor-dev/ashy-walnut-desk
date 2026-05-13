defmodule AshyWalnutDesk.Identity.Changes.SoftDelete do
  @moduledoc """
  Shared `Ash.Resource.Change` that sets `deleted_at = utc_now()` when the
  attribute is currently nil and is a no-op otherwise. Used by every
  Identity-axis archive action so a double-archive never bumps the
  timestamp (ADR-019).
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      case Changeset.get_attribute(changeset, :deleted_at) do
        nil -> Changeset.force_change_attribute(changeset, :deleted_at, DateTime.utc_now())
        _already_archived -> changeset
      end
    end)
  end
end
