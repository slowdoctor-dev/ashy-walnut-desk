defmodule AshyWalnutDesk.Interaction.InboundDeliveryDedupeTest do
  @moduledoc """
  Story 3.4 AC1 — Twilio retries with the same MessageSid don't
  re-create chain rows.
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures

  alias AshyWalnutDesk.Interaction.{
    Channel,
    Conversation,
    InboundDelivery,
    InboundIntake,
    InboundMessage,
    Inbox,
    Message
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

  defp inbound(sid) do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: sid,
      from: "+15551234567",
      to: "+15557654321",
      body: "msg",
      received_at: DateTime.utc_now()
    }
  end

  test "duplicate MessageSid does not re-create chain rows", %{channel: channel} do
    sid = "SM" <> String.duplicate("a", 32)

    assert {:ok, %{outcome: :processed}} = InboundIntake.intake(inbound(sid), channel)
    assert {:ok, %{outcome: :duplicate}} = InboundIntake.intake(inbound(sid), channel)
    assert {:ok, %{outcome: :duplicate}} = InboundIntake.intake(inbound(sid), channel)

    inbox_count =
      Inbox |> Ash.Query.for_read(:read, %{}, authorize?: false) |> Ash.count!(authorize?: false)

    msg_count =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.count!(authorize?: false)

    convo_count =
      Conversation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.count!(authorize?: false)

    assert inbox_count == 1
    assert msg_count == 1
    assert convo_count == 1
  end

  test "unique index enforces (provider, provider_message_id) at DB level", _ctx do
    sid = "SM" <> String.duplicate("b", 32)

    {:ok, _first} =
      Ash.create(
        InboundDelivery,
        %{
          provider: :twilio,
          provider_message_id: sid,
          outcome: :processed
        },
        action: :record_delivery,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    assert {:error, _} =
             Ash.create(
               InboundDelivery,
               %{
                 provider: :twilio,
                 provider_message_id: sid,
                 outcome: :processed
               },
               action: :record_delivery,
               authorize?: false,
               context: %{from_inbound_webhook: true}
             )
  end

  test "different providers can share the same provider_message_id", _ctx do
    sid = "ID-shared-123"

    {:ok, _twilio} =
      Ash.create(
        InboundDelivery,
        %{provider: :twilio, provider_message_id: sid, outcome: :processed},
        action: :record_delivery,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    assert {:ok, _stub} =
             Ash.create(
               InboundDelivery,
               %{provider: :stub, provider_message_id: sid, outcome: :processed},
               action: :record_delivery,
               authorize?: false,
               context: %{from_inbound_webhook: true}
             )
  end
end
