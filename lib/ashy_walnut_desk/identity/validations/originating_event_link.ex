defmodule AshyWalnutDesk.Identity.Validations.OriginatingEventLink do
  @moduledoc """
  Enforces the follow-up contract on `Appointment` (architecture §3.3):

  * `appointment_type == :follow_up` requires `originating_event_id`.
  * Any other `appointment_type` must leave `originating_event_id` nil.
  """

  use Ash.Resource.Validation

  alias Ash.Changeset

  @impl true
  def validate(changeset, _opts, _context) do
    type = Changeset.get_attribute(changeset, :appointment_type)
    link = Changeset.get_attribute(changeset, :originating_event_id)

    case {type, link} do
      {:follow_up, nil} ->
        {:error,
         field: :originating_event_id, message: "is required when appointment_type is :follow_up"}

      {:follow_up, _id} ->
        :ok

      {_other, nil} ->
        :ok

      {_other, _id} ->
        {:error,
         field: :originating_event_id,
         message: "must be nil unless appointment_type is :follow_up"}
    end
  end
end
