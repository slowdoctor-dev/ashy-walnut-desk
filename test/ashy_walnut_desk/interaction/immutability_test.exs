defmodule AshyWalnutDesk.Interaction.ImmutabilityTest do
  use AshyWalnutDesk.DataCase, async: true

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Interaction.{Action, AuditEvent, Compensation}

  @immutable_resources [Action, Compensation, AuditEvent]

  test "immutable chain resources expose only read/create/update workflow actions" do
    Enum.each(@immutable_resources, fn resource ->
      action_names = resource |> Info.actions() |> Enum.map(& &1.name)

      refute :archive in action_names
      refute :recover in action_names
      refute :destroy in action_names
    end)
  end

  test "immutable chain resources do not expose deleted_at" do
    Enum.each(@immutable_resources, fn resource ->
      assert is_nil(Info.attribute(resource, :deleted_at))
    end)
  end
end
