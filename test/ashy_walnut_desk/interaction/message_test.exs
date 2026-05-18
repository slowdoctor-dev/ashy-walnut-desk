defmodule AshyWalnutDesk.Interaction.MessageTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.{SystemActor, User}
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

  test "rejects direct inbound (story 3.3 ADR-024) and rejects direct outbound" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    {:ok, conversation} = setup_conversation(admin, operator)

    # ADR-024: inbound rows are intake-only — operator cannot create
    # them directly. Webhook controller passes from_inbound_webhook
    # context; this test asserts the operator-direct path is blocked.
    assert {:error, inbound_error} =
             Ash.create(
               Message,
               %{conversation_id: conversation.id, direction: :inbound, body: "hello"},
               action: :record_message,
               actor: operator
             )

    assert Exception.message(inbound_error) =~ "webhook intake path"

    # Outbound also rejected — must go through Action.execute.
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

  test "inbound accepted with from_inbound_webhook context (system actor path)" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    system_actor = SystemActor.ensure!()

    {:ok, conversation} = setup_conversation(admin, operator)

    assert {:ok, inbound} =
             Ash.create(
               Message,
               %{conversation_id: conversation.id, direction: :inbound, body: "via webhook"},
               action: :record_message,
               actor: system_actor,
               authorize?: false,
               context: %{from_inbound_webhook: true}
             )

    assert inbound.direction == :inbound
  end
end
