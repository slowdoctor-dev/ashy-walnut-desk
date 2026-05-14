defmodule AshyWalnutDesk.Identity.Validations.OriginatingEventLink do
  @moduledoc """
  Enforces the follow-up contract on `Appointment` (architecture §3.3):

  * `appointment_type == :follow_up` requires `originating_event_id`.
  * Any other `appointment_type` must leave `originating_event_id` nil.
  * When set, the originating Event must belong to the same Identity
    as the Appointment. The FK constraint alone cannot catch a
    cross-Identity link (both rows exist; only the relationship is
    wrong), so we read the Event and compare `identity_id` here.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset
  alias AshyWalnutDesk.Identity.Event

  @impl true
  def validate(changeset, _opts, _context) do
    type = Changeset.get_attribute(changeset, :appointment_type)
    link = Changeset.get_attribute(changeset, :originating_event_id)
    identity_id = Changeset.get_attribute(changeset, :identity_id)

    case check_pairing(type, link) do
      :ok -> check_same_identity(link, identity_id)
      error -> error
    end
  end

  defp check_pairing(:follow_up, nil) do
    {:error,
     field: :originating_event_id, message: "is required when appointment_type is :follow_up"}
  end

  defp check_pairing(:follow_up, _id), do: :ok
  defp check_pairing(_other, nil), do: :ok

  defp check_pairing(_other, _id) do
    {:error,
     field: :originating_event_id, message: "must be nil unless appointment_type is :follow_up"}
  end

  defp check_same_identity(nil, _identity_id), do: :ok
  defp check_same_identity(_event_id, nil), do: :ok

  defp check_same_identity(event_id, identity_id) do
    # Use :read_with_archived so a soft-deleted event from a foreign
    # Identity still trips the check (default read would silently drop
    # it and the validation would pass).
    case Ash.get(Event, event_id, action: :read_with_archived, authorize?: false) do
      {:ok, %{identity_id: ^identity_id}} ->
        :ok

      {:ok, _other_identity} ->
        {:error,
         field: :originating_event_id,
         message: "must belong to the same identity as the appointment"}

      {:error, _} ->
        # Unknown id — the FK constraint will reject it at write time.
        :ok
    end
  end
end
