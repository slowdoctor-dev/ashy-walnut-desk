defmodule AshyWalnutDesk.Interaction.Adapters.Stub do
  @moduledoc """
  Phase 2's no-op adapter. Still in use for tests and demo seeds
  that don't need real provider behavior. Phase 3 added the inbound
  callbacks; the stub satisfies them as no-ops too.
  """

  @behaviour AshyWalnutDesk.Interaction.Adapter

  alias AshyWalnutDesk.Interaction.InboundMessage

  @impl true
  def channel_slug, do: "stub"

  @impl true
  def send_outbound(_message, _channel), do: {:ok, %{stub: true}}

  @impl true
  def verify_inbound_signature(_url, _params, _signature, _secret), do: :ok

  @impl true
  def parse_inbound(%{"id" => id, "from" => from, "to" => to, "body" => body}) do
    {:ok,
     %InboundMessage{
       provider: :stub,
       provider_message_id: id,
       from: from,
       to: to,
       body: body,
       received_at: DateTime.utc_now()
     }}
  end

  def parse_inbound(_), do: {:error, :missing_required_fields}
end
