defmodule AshyWalnutDesk.Interaction.Adapters.AdapterContractTest do
  @moduledoc """
  Story 3.2 AC1+AC2 — runs Twilio and Echo (and Stub as a bonus)
  through the same shape of conformance scenarios. If a future
  provider lands as `Adapters.<Provider>` and is added to the
  allowlist, dropping it into `@adapters_under_test` exercises the
  same checks.

  This is the proof-of-shape that `Interaction.Adapter` is a real
  behavior contract, not a single-impl tautology. Phase 3 ships
  three implementations: Stub (legacy / dev), Twilio (real
  outbound + real inbound signature), Echo (test fixture).
  """

  use ExUnit.Case, async: true

  alias AshyWalnutDesk.Interaction.Adapter
  alias AshyWalnutDesk.Interaction.Adapters.{Echo, Stub, Twilio}
  alias AshyWalnutDesk.Interaction.{Channel, InboundMessage, Message}

  @adapters_under_test [Stub, Echo, Twilio]

  describe "the Adapter behavior" do
    test "declares the four required callbacks" do
      callbacks = Adapter.behaviour_info(:callbacks)

      assert {:channel_slug, 0} in callbacks
      assert {:send_outbound, 2} in callbacks
      assert {:verify_inbound_signature, 4} in callbacks
      assert {:parse_inbound, 1} in callbacks
    end
  end

  for adapter <- @adapters_under_test do
    describe "#{inspect(adapter)} adapter conformance" do
      @describetag adapter: adapter

      test "channel_slug/0 returns a non-empty string", _ctx do
        slug = unquote(adapter).channel_slug()
        assert is_binary(slug)
        assert byte_size(slug) > 0
      end

      test "send_outbound/2 with a valid message + channel returns {:ok, map}", _ctx do
        message = %Message{
          conversation_id: Ash.UUID.generate(),
          direction: :outbound,
          body: "test outbound body",
          approved_by_id: Ash.UUID.generate()
        }

        channel = %Channel{
          slug: unquote(adapter).channel_slug(),
          adapter_module: Atom.to_string(unquote(adapter)),
          enabled?: true
        }

        result = unquote(adapter).send_outbound(message, channel)

        assert {:ok, response} = result

        assert is_map(response),
               "#{inspect(unquote(adapter))} returned non-map response: #{inspect(response)}"
      end

      test "parse_inbound/1 with valid provider-shaped payload returns {:ok, %InboundMessage{}}",
           _ctx do
        result = unquote(adapter).parse_inbound(provider_payload(unquote(adapter)))

        assert {:ok, %InboundMessage{} = inbound} = result

        for required_field <- [:provider, :provider_message_id, :from, :to, :body, :received_at] do
          refute is_nil(Map.fetch!(inbound, required_field)),
                 "#{inspect(unquote(adapter))} omitted #{inspect(required_field)} from InboundMessage"
        end

        assert is_atom(inbound.provider)
        assert is_binary(inbound.provider_message_id)
        assert %DateTime{} = inbound.received_at
      end

      test "parse_inbound/1 with empty / malformed payload returns {:error, _}", _ctx do
        for bad <- [%{}, nil, "not a map", []] do
          assert match?({:error, _}, unquote(adapter).parse_inbound(bad)),
                 "#{inspect(unquote(adapter))} did not reject malformed: #{inspect(bad)}"
        end
      end

      test "verify_inbound_signature/4 is callable and returns :ok | {:error, atom}", _ctx do
        url = "https://example.com/webhook"
        params = %{"From" => "+15551234567", "Body" => "hi"}
        signature = "Yzg2YmJjY2Y2NTQzN2M2NTczNzhmNzM2NWZjNzVjNDIzZjBjYzVlOQ=="
        secret = "dev-only-secret"

        result = unquote(adapter).verify_inbound_signature(url, params, signature, secret)

        case result do
          :ok -> :ok
          {:error, atom} when is_atom(atom) -> :ok
        end
      end
    end
  end

  describe "extension-point isolation (AC3)" do
    test "an allowlist-registered third-party adapter participates without core edits" do
      defmodule TestThirdPartyAdapter do
        @moduledoc false
        @behaviour Adapter

        @impl true
        def channel_slug, do: "third-party-test"

        @impl true
        def send_outbound(_message, _channel), do: {:ok, %{provider: :third_party}}

        @impl true
        def verify_inbound_signature(_url, _params, _sig, _secret), do: :ok

        @impl true
        def parse_inbound(payload) when is_map(payload) and map_size(payload) > 0 do
          {:ok,
           %InboundMessage{
             provider: :third_party,
             provider_message_id: payload["id"] || "tp-#{System.unique_integer([:positive])}",
             from: payload["from"] || "tp-sender",
             to: payload["to"] || "tp-recipient",
             body: payload["body"] || "",
             received_at: DateTime.utc_now()
           }}
        end

        def parse_inbound(_), do: {:error, :invalid_payload}
      end

      callbacks = Adapter.behaviour_info(:callbacks)
      adapter_callbacks = TestThirdPartyAdapter.__info__(:functions)

      for {name, arity} <- callbacks do
        assert {name, arity} in adapter_callbacks,
               "third-party adapter missing #{name}/#{arity}"
      end

      message = %Message{
        conversation_id: Ash.UUID.generate(),
        direction: :outbound,
        body: "isolation test",
        approved_by_id: Ash.UUID.generate()
      }

      channel = %Channel{slug: "third-party-test", enabled?: true}

      assert {:ok, %{provider: :third_party}} =
               TestThirdPartyAdapter.send_outbound(message, channel)

      assert {:ok, %InboundMessage{provider: :third_party}} =
               TestThirdPartyAdapter.parse_inbound(%{"from" => "x", "body" => "y"})
    end
  end

  defp provider_payload(Stub),
    do: %{"id" => "stub-1", "from" => "stub-a", "to" => "stub-b", "body" => "hi"}

  defp provider_payload(Echo),
    do: %{
      "id" => "echo-1",
      "from" => "echo-a",
      "to" => "echo-b",
      "body" => "hi",
      "received_at" => "2026-05-18T00:00:00Z"
    }

  defp provider_payload(Twilio),
    do: %{
      "MessageSid" => "SM" <> String.duplicate("0", 32),
      "From" => "+15551234567",
      "To" => "+15557654321",
      "Body" => "hi from twilio"
    }
end
