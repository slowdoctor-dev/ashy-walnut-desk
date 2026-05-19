defmodule AshyWalnutDesk.Interaction.Adapters.TwilioRecipientHardeningTest do
  @moduledoc """
  Story 3.fix — `Adapters.Twilio.send_outbound/2` must refuse to send
  when the in-memory Message has no preloaded
  `conversation.identity.primary_identifier`. Pre-fix the adapter
  fell back to a hardcoded "+15550000000" recipient and every
  outbound SMS in prod would have silently misrouted.
  """

  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.Adapters.Twilio
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Message}

  defp channel,
    do: %Channel{
      slug: "twilio-sms",
      adapter_module: Atom.to_string(Twilio),
      enabled?: true
    }

  test "missing conversation → {:error, :permanent} (no HTTP call)" do
    message = %Message{
      conversation_id: Ash.UUID.generate(),
      direction: :outbound,
      body: "hi",
      approved_by_id: Ash.UUID.generate(),
      outbound_idempotency_key: "action-test"
    }

    assert {:error, :permanent} = Twilio.send_outbound(message, channel())
  end

  test "missing identity inside conversation → {:error, :permanent}" do
    message = %Message{
      conversation_id: Ash.UUID.generate(),
      conversation: %Conversation{id: Ash.UUID.generate()},
      direction: :outbound,
      body: "hi",
      approved_by_id: Ash.UUID.generate(),
      outbound_idempotency_key: "action-test"
    }

    assert {:error, :permanent} = Twilio.send_outbound(message, channel())
  end

  test "empty primary_identifier → {:error, :permanent}" do
    message = %Message{
      conversation_id: Ash.UUID.generate(),
      conversation: %Conversation{
        id: Ash.UUID.generate(),
        identity: %Identity{id: Ash.UUID.generate(), primary_identifier: ""}
      },
      direction: :outbound,
      body: "hi",
      approved_by_id: Ash.UUID.generate(),
      outbound_idempotency_key: "action-test"
    }

    assert {:error, :permanent} = Twilio.send_outbound(message, channel())
  end

  test "well-formed identifier → adapter calls the configured plug (stubbed in test_helper)" do
    message = %Message{
      conversation_id: Ash.UUID.generate(),
      conversation: %Conversation{
        id: Ash.UUID.generate(),
        identity: %Identity{
          id: Ash.UUID.generate(),
          primary_identifier: "+15551234567"
        }
      },
      direction: :outbound,
      body: "hi",
      approved_by_id: Ash.UUID.generate(),
      outbound_idempotency_key: "action-test"
    }

    assert {:ok, payload} = Twilio.send_outbound(message, channel())
    assert is_map(payload)
  end
end
