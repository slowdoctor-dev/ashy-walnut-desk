defmodule AshyWalnutDesk.Interaction.Adapter do
  @moduledoc """
  Behaviour for channel adapters. Phase 2 ships only the `Stub`
  implementation (see `AshyWalnutDesk.Interaction.Adapters.Stub`);
  Phase 3 will add the first real channel.

  ## Stub adapter module name

  The single fixture adapter is referenced by string from:

  - `config :ashy_walnut_desk, :channel_adapters` (allowlist)
  - `Channel.adapter_module` attribute (per-row config)
  - test fixtures + demo seeds (`stub-N` channel slug)

  Use `Adapter.stub_module_string/0` as the canonical reference
  instead of hardcoding `"AshyWalnutDesk.Interaction.Adapters.Stub"`
  in those callsites. Closes A1 from the simplicity review.
  """

  alias AshyWalnutDesk.Interaction.{Channel, Message}

  @stub_module AshyWalnutDesk.Interaction.Adapters.Stub

  @callback send_outbound(message :: Message.t(), channel :: Channel.t()) ::
              {:ok, map()} | {:error, term()}
  @callback channel_slug() :: String.t()

  @doc """
  The canonical module-name string for the Phase 2 stub adapter.
  Use this in fixtures, demo seeds, and any code that needs to
  register a `Channel` row pointing at the stub.
  """
  @spec stub_module_string() :: String.t()
  def stub_module_string, do: Atom.to_string(@stub_module)
end
