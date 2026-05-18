defmodule AshyWalnutDesk.Interaction.ReplayAuditOutcomeTest do
  @moduledoc """
  Story 3.4 AC3 — replay attempts have deterministic outcomes
  visible in the InboundDelivery ledger: :processed, :duplicate,
  :failed_intake.
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query
  import Ash.Expr

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Channel, InboundDelivery, InboundIntake, InboundMessage}

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

  defp inbound(sid, from \\ "+15551112222") do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: sid,
      from: from,
      to: "+15557654321",
      body: "test",
      received_at: DateTime.utc_now()
    }
  end

  test "first delivery records :processed outcome", %{channel: channel} do
    sid = "SM" <> String.duplicate("c", 32)
    {:ok, _} = InboundIntake.intake(inbound(sid), channel)

    [delivery] =
      InboundDelivery
      |> Ash.Query.filter(expr(provider_message_id == ^sid))
      |> Ash.read!(authorize?: false)

    assert delivery.outcome == :processed
    refute delivery.intake_failure_reason
  end

  test "duplicate delivery returns :duplicate without new ledger row", %{channel: channel} do
    sid = "SM" <> String.duplicate("d", 32)
    {:ok, _} = InboundIntake.intake(inbound(sid), channel)
    {:ok, %{outcome: :duplicate}} = InboundIntake.intake(inbound(sid), channel)

    deliveries =
      InboundDelivery
      |> Ash.Query.filter(expr(provider_message_id == ^sid))
      |> Ash.read!(authorize?: false)

    assert length(deliveries) == 1
  end

  test "failed intake records :failed_intake with reason", %{channel: channel} do
    sid = "SM" <> String.duplicate("e", 32)
    # Empty From → missing_from failure path
    assert {:error, :missing_from} = InboundIntake.intake(inbound(sid, ""), channel)

    [delivery] =
      InboundDelivery
      |> Ash.Query.filter(expr(provider_message_id == ^sid))
      |> Ash.read!(authorize?: false)

    assert delivery.outcome == :failed_intake
    assert delivery.intake_failure_reason =~ "missing_from"
  end

  test "InboundDelivery read policy admin-only" do
    operator = AccountsFixtures.create_user(:operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             InboundDelivery |> Ash.read(actor: operator)
  end
end
