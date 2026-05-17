defmodule AshyWalnutDesk.Interaction.Validations.ConversationIdentityAlive do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias AshyWalnutDesk.Identity.Identity

  @impl true
  def validate(changeset, _opts, _context) do
    case Changeset.get_attribute(changeset, :identity_id) do
      nil ->
        :ok

      identity_id ->
        case Ash.get(Identity, identity_id, action: :read_with_archived, authorize?: false) do
          {:ok, %{deleted_at: nil}} ->
            :ok

          {:ok, _archived_identity} ->
            {:error, field: :identity_id, message: "cannot reference archived identity"}

          {:error, _error} ->
            {:error, field: :identity_id, message: "does not reference a valid identity"}
        end
    end
  end
end
