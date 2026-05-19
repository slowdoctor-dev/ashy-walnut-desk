defmodule AshyWalnutDesk.Interaction.ChannelVisibilityTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Channel

  test "viewer cannot read Channel.adapter_module" do
    admin = AccountsFixtures.create_user(:admin)
    viewer = AccountsFixtures.create_user(:viewer)

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-#{System.unique_integer([:positive])}",
          display_name: "Twilio",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, viewer_channel} = Ash.get(Channel, channel.id, actor: viewer)
    assert match?(%Ash.ForbiddenField{}, viewer_channel.adapter_module)
  end

  test "operator can read Channel.adapter_module" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{System.unique_integer([:positive])}",
          display_name: "Stub",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, operator_channel} = Ash.get(Channel, channel.id, actor: operator)
    assert operator_channel.adapter_module == "AshyWalnutDesk.Interaction.Adapters.Stub"
  end
end
