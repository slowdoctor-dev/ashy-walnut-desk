defmodule AshyWalnutDesk.Interaction.Adapters.Stub do
  @moduledoc false

  @behaviour AshyWalnutDesk.Interaction.Adapter

  @impl true
  def channel_slug, do: "stub"

  @impl true
  def send_outbound(_message, _channel), do: {:ok, %{stub: true}}
end
