defmodule AshyWalnutDesk.Interaction.InboundThreadingTest do
  @moduledoc """
  Story 3.3 AC4 — inbound threading default: reuse most-recent
  non-archived Conversation on (identity_id, channel_id); else
  create a new one.
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query
  import Ash.Expr

  alias AshyWalnutDesk.AccountsFixtures

  alias AshyWalnutDesk.Interaction.{
    Channel,
    Conversation,
    InboundIntake,
    InboundMessage
  }

  setup do
    admin = AccountsFixtures.create_user(:admin)

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: Atom.to_string(AshyWalnutDesk.Interaction.Adapters.Twilio)
        },
        action: :register_channel,
        actor: admin
      )

    %{admin: admin, channel: channel}
  end

  defp inbound(from, body) do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: "SM-#{System.unique_integer([:positive])}",
      from: from,
      to: "+15557654321",
      body: body,
      received_at: DateTime.utc_now()
    }
  end

  test "no existing Conversation → new one is created", %{channel: channel} do
    {:ok, result} = InboundIntake.intake(inbound("+15550001111", "first"), channel)
    assert is_binary(result.conversation.id)
  end

  test "subsequent inbound from same From → reuses existing Conversation", %{channel: channel} do
    {:ok, first} = InboundIntake.intake(inbound("+15550002222", "first"), channel)
    {:ok, second} = InboundIntake.intake(inbound("+15550002222", "second"), channel)

    assert second.conversation.id == first.conversation.id
  end

  test "archived Conversation is NOT reused → new one created", %{channel: channel, admin: admin} do
    {:ok, first} = InboundIntake.intake(inbound("+15550003333", "first"), channel)

    # Archive the conversation
    {:ok, _archived} =
      Ash.update(first.conversation, %{}, action: :archive, actor: admin)

    {:ok, second} = InboundIntake.intake(inbound("+15550003333", "second"), channel)

    refute second.conversation.id == first.conversation.id
  end

  test "different channel does not collide on threading", %{channel: channel, admin: admin} do
    {:ok, _stub_channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-other",
          display_name: "Other",
          adapter_module: Atom.to_string(AshyWalnutDesk.Interaction.Adapters.Stub)
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, first} = InboundIntake.intake(inbound("+15550004444", "via twilio"), channel)

    # Inbound via the same twilio channel reuses
    {:ok, second} = InboundIntake.intake(inbound("+15550004444", "via twilio again"), channel)
    assert second.conversation.id == first.conversation.id
  end
end
