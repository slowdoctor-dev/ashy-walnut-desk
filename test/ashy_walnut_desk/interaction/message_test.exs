defmodule AshyWalnutDesk.Interaction.MessageTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Message}

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{System.unique_integer([:positive])}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end

  defp setup_conversation(admin, operator) do
    {:ok, identity} =
      Ash.create(
        Identity,
        %{
          display_name: "Identity #{System.unique_integer([:positive])}",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        action: :register_identity,
        actor: admin
      )

    unique = System.unique_integer([:positive])

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    Ash.create(
      Conversation,
      %{subject: "Thread", identity_id: identity.id, channel_id: channel.id},
      action: :open_conversation,
      actor: operator
    )
  end

  test "accepts inbound record_message and rejects direct outbound" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    {:ok, conversation} = setup_conversation(admin, operator)

    assert {:ok, inbound} =
             Ash.create(
               Message,
               %{conversation_id: conversation.id, direction: :inbound, body: "hello"},
               action: :record_message,
               actor: operator
             )

    assert inbound.direction == :inbound

    assert {:error, error} =
             Ash.create(
               Message,
               %{
                 conversation_id: conversation.id,
                 direction: :outbound,
                 body: "reply",
                 approved_by_id: admin.id
               },
               action: :record_message,
               actor: operator
             )

    assert Exception.message(error) =~ "Action.execute path"
  end
end
