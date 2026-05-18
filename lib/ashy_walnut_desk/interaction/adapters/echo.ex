defmodule AshyWalnutDesk.Interaction.Adapters.Echo do
  @moduledoc """
  Test-only adapter that echoes any inbound payload back as a
  canonical `InboundMessage` and accepts any outbound send. Used by
  the adapter-contract conformance test alongside `Adapters.Twilio`
  — proves the `Interaction.Adapter` behavior isn't a single-impl
  tautology and that adding a future provider via the allowlist
  works at runtime.

  Not allowed in prod. The `:channel_adapters` allowlist in
  `config/prod.exs` (when added by a deployer) deliberately omits
  Echo; only `config/test.exs` includes it for the conformance
  suite.

  See `specs/phase-3/architecture.md §1 (Adapters.Echo)`, ADR-022,
  and story 3.2 AC2.
  """

  @behaviour AshyWalnutDesk.Interaction.Adapter

  alias AshyWalnutDesk.Interaction.InboundMessage

  @impl true
  def channel_slug, do: "echo"

  @impl true
  def send_outbound(message, _channel) do
    {:ok,
     %{
       provider: :echo,
       echoed_body: message.body,
       echoed_at: DateTime.utc_now() |> DateTime.to_iso8601()
     }}
  end

  @impl true
  def verify_inbound_signature(_url, _params, _signature, _secret), do: :ok

  @impl true
  def parse_inbound(%{"id" => id, "from" => from, "to" => to, "body" => body} = payload) do
    {:ok,
     %InboundMessage{
       provider: :echo,
       provider_message_id: id,
       from: from,
       to: to,
       body: body,
       received_at: parse_received_at(payload["received_at"])
     }}
  end

  def parse_inbound(_), do: {:error, :missing_required_fields}

  defp parse_received_at(nil), do: DateTime.utc_now()

  defp parse_received_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
end
