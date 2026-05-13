defmodule AshyWalnutDesk.Identity.Changes.HashPrimaryIdentifier do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.before_action(changeset, fn changeset ->
      case Changeset.get_argument(changeset, :primary_identifier) do
        nil ->
          changeset

        raw ->
          normalized = raw |> to_string() |> String.trim() |> String.downcase()
          salt = Application.fetch_env!(:ashy_walnut_desk, :identifier_hash_salt)
          hash = :crypto.hash(:sha256, normalized <> salt) |> Base.encode16(case: :lower)
          Changeset.force_change_attribute(changeset, :primary_identifier_hash, hash)
      end
    end)
  end
end
