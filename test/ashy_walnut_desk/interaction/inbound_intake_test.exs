defmodule AshyWalnutDesk.Interaction.InboundIntakeTest do
  @moduledoc """
  Story 3.3 AC2 — InboundIntake creates/links Conversation + Inbox +
  inbound Message via named Ash actions only, using the internal
  inbound Inbox path (Inbox.:record_inbound, not :record_inbox).
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.SystemActor
  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Adapter,
    Channel,
    Conversation,
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

  defp inbound(opts \\ []) do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: opts[:sid] || "SM" <> String.duplicate("0", 32),
      from: opts[:from] || "+15551234567",
      to: opts[:to] || "+15557654321",
      body: opts[:body] || "test body",
      received_at: DateTime.utc_now()
    }
  end

  test "intake creates Conversation + Inbox + inbound Message", %{channel: channel} do
    assert {:ok, result} = InboundIntake.intake(inbound(), channel)

    assert %Conversation{} = result.conversation
    assert %Inbox{status: :open} = result.inbox
    assert %Message{direction: :inbound, body: "test body"} = result.message

    assert result.inbox.conversation_id == result.conversation.id
    assert result.message.conversation_id == result.conversation.id
  end

  test "inbox is created via :record_inbound (not :record_inbox)", %{channel: channel} do
    {:ok, result} = InboundIntake.intake(inbound(body: "via record_inbound"), channel)

    versions =
      Inbox.Version
      |> Ash.Query.filter(version_source_id: result.inbox.id)
      |> Ash.read!(action: :read, authorize?: false)

    assert Enum.any?(versions, &(&1.version_action_name == :record_inbound))
    refute Enum.any?(versions, &(&1.version_action_name == :record_inbox))
  end

  test "operator-only :record_inbox is rejected when called without operator actor", %{
    channel: channel,
    admin: admin
  } do
    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{
          subject: "x",
          identity_id: nil_identity_id!(admin),
          channel_id: channel.id
        }
        |> maybe_drop_nil(),
        action: :open_conversation,
        actor: admin
      )

    # Confirms the operator-only path is structurally separate: it
    # cannot be invoked via the internal context, only via an
    # operator/admin role.
    system_actor = SystemActor.ensure!()

    result =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "should not work"},
        action: :record_inbox,
        actor: system_actor,
        context: %{from_inbound_webhook: true}
      )

    assert {:error, %Ash.Error.Forbidden{}} = result
  end

  defp nil_identity_id!(admin) do
    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "fixture", primary_identifier: "+15550000001"},
        action: :register_identity,
        actor: admin
      )

    identity.id
  end

  defp maybe_drop_nil(attrs), do: Map.reject(attrs, fn {_, v} -> is_nil(v) end)

  test "Adapter behaviour callbacks include parse_inbound", _ctx do
    callbacks = Adapter.behaviour_info(:callbacks)
    assert {:parse_inbound, 1} in callbacks
  end
end
