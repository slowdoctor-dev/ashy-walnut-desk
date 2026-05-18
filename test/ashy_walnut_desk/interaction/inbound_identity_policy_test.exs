defmodule AshyWalnutDesk.Interaction.InboundIdentityPolicyTest do
  @moduledoc """
  Story 3.3 AC3 — inbound identity matching defaults:
  (a) existing identifier → link existing Identity
  (b) unknown identifier → create provisional Identity
  (c) malformed → deterministic auditable failure path
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.{Identity, ProvisionalNamer}
  alias AshyWalnutDesk.Interaction.{Channel, InboundIntake, InboundMessage}

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

  defp inbound(from, body \\ "msg") do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: "SM-#{System.unique_integer([:positive])}",
      from: from,
      to: "+15557654321",
      body: body,
      received_at: DateTime.utc_now()
    }
  end

  test "(a) existing identifier links to the existing Identity", %{channel: channel, admin: admin} do
    {:ok, existing} =
      Ash.create(
        Identity,
        %{display_name: "Existing", primary_identifier: "+15551234567"},
        action: :register_identity,
        actor: admin
      )

    assert {:ok, result} = InboundIntake.intake(inbound("+15551234567"), channel)

    assert result.identity.id == existing.id
    refute result.provisional?
  end

  test "(b) unknown identifier creates a provisional Identity with deterministic name", %{
    channel: channel
  } do
    assert {:ok, result} = InboundIntake.intake(inbound("+15559998888"), channel)

    assert result.provisional?
    assert result.identity.provisional? == true
    assert result.identity.discovered_via == :inbound_webhook

    display = to_string(result.identity.display_name)
    assert display =~ "Inbound"
    assert display =~ "+1 555"
    assert display =~ "8888"
  end

  test "(c) malformed identifier (empty From) lands in deterministic failure path", %{
    channel: channel
  } do
    assert {:error, :missing_from} = InboundIntake.intake(inbound(""), channel)
  end

  test "ProvisionalNamer formats US E.164 with masked middle", _ctx do
    assert ProvisionalNamer.name("+15551234567") =~ "+1 555 *** 4567"
  end

  test "ProvisionalNamer masks non-phone identifiers with first-3 / last-3", _ctx do
    assert ProvisionalNamer.name("abcdefghijk") =~ "abc***ijk"
  end
end
