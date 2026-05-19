defmodule AshyWalnutDesk.Interaction.InboundIntakeRaceTest do
  @moduledoc """
  Story 3.fix — two concurrent webhook requests with the same
  `MessageSid` must result in:
  - exactly ONE successful intake (`outcome: :processed`)
  - one `:duplicate` outcome for the loser
  - zero `:failed_intake` rows
  - exactly one chain (Inbox + inbound Message + Conversation)

  Pre-fix the loser's transaction rolled back its chain rows but
  then tried to write a `:failed_intake` row — the duplicate-as-
  failure misreport. The fix moves the `InboundDelivery` insert to
  the start of the transaction so the unique constraint catches
  the race before any chain work happens.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
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

  alias AshyWalnutDesk.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    admin = AccountsFixtures.create_user(:admin)

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio"
        },
        action: :register_channel,
        actor: admin
      )

    %{channel: channel}
  end

  defp inbound(sid) do
    %InboundMessage{
      provider: :twilio,
      provider_message_id: sid,
      from: "+15551239999",
      to: "+15557654321",
      body: "race test",
      received_at: DateTime.utc_now()
    }
  end

  test "concurrent same-sid intakes: one :processed, one :duplicate, no failure rows", %{
    channel: channel
  } do
    sid = "SM" <> String.duplicate("z", 32)
    parent = self()

    [task_a, task_b] =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.allow(Repo, parent, self())
          InboundIntake.intake(inbound(sid), channel)
        end)
      end

    results = Task.await_many([task_a, task_b], 10_000)

    outcomes =
      Enum.map(results, fn
        {:ok, %{outcome: o}} -> o
        other -> other
      end)

    # Both calls returned ok; exactly one :processed and one
    # :duplicate. (Order varies — that's the race.)
    assert Enum.sort(outcomes) == [:duplicate, :processed]

    # Exactly one InboundDelivery row, outcome :processed. No
    # `:failed_intake` row from the loser's rolled-back transaction.
    deliveries =
      InboundDelivery
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(provider_message_id == ^sid))
      |> Ash.read!(authorize?: false)

    assert length(deliveries) == 1
    assert hd(deliveries).outcome == :processed
    refute hd(deliveries).intake_failure_reason

    # Exactly one chain.
    assert one_row?(Inbox)
    assert one_row?(Message)
    assert one_row?(Conversation)
  end

  defp one_row?(resource) do
    resource
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.count!(authorize?: false)
    |> Kernel.==(1)
  end
end
