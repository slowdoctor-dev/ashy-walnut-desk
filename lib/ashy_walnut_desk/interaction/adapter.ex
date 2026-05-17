defmodule AshyWalnutDesk.Interaction.Adapter do
  @moduledoc false

  alias AshyWalnutDesk.Interaction.{Channel, Message}

  @callback send_outbound(message :: Message.t(), channel :: Channel.t()) ::
              {:ok, map()} | {:error, term()}
  @callback channel_slug() :: String.t()
end
