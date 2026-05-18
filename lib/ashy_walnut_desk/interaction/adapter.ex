defmodule AshyWalnutDesk.Interaction.Adapter do
  @moduledoc """
  The single extension point for channel providers. Phase 2 shipped
  the stub adapter; Phase 3 adds Twilio (real SMS) and Echo
  (test-only fixture). Future providers (WhatsApp, Line, KakaoTalk)
  land as single-file `Adapters.<Provider>` modules implementing
  this behavior plus an entry in the `:channel_adapters` allowlist.

  The contract has two halves:

  - **Outbound** — `send_outbound/2` invoked by `Jobs.OutboundSend`
    (story 3.5). Returns `{:ok, payload}` for success or
    `{:error, term}` for failure. Transient errors trigger Oban
    retry per ADR-023; permanent errors mark the Action
    `:failed`.

  - **Inbound** — `verify_inbound_signature/4` + `parse_inbound/1`
    called by the webhook controller (story 3.3). Signature
    verification gates the request; parse_inbound lifts the
    provider-native payload into the canonical
    `Interaction.InboundMessage` struct so downstream intake
    logic is provider-agnostic.

  ## Stub adapter module name

  `Adapter.stub_module_string/0` is the canonical reference for
  `"AshyWalnutDesk.Interaction.Adapters.Stub"` used in fixtures and
  demo seeds. Closes A1 from the simplicity review (PR #39).
  """

  alias AshyWalnutDesk.Interaction.{Channel, InboundMessage, Message}

  @stub_module AshyWalnutDesk.Interaction.Adapters.Stub

  @doc """
  Provider slug used to look up the `Channel` row for this adapter.
  Stable identifier; deployers register Channels with this slug.
  Example: `"twilio-sms"`, `"echo"`, `"stub"`.
  """
  @callback channel_slug() :: String.t()

  @doc """
  Send the outbound message through the provider. Returns
  `{:ok, payload_map}` on success (payload stored on
  `Action.adapter_response`); `{:error, :transient | :permanent | any}`
  on failure. Transient errors trigger Oban retry; permanent
  errors mark the Action `:failed`.
  """
  @callback send_outbound(message :: Message.t(), channel :: Channel.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Verify a webhook request's authenticity. Receives the public URL
  the provider posted to, the parsed form/JSON params, the signature
  header, and the secret. Returns `:ok` on valid signature or
  `{:error, atom}` on rejection. The controller logs and audits
  rejections without touching the chain.
  """
  @callback verify_inbound_signature(
              full_url :: String.t(),
              params :: map(),
              signature :: String.t() | nil,
              secret :: String.t()
            ) :: :ok | {:error, atom()}

  @doc """
  Parse the provider-native inbound payload into the canonical
  `InboundMessage` struct. Returns `{:ok, message}` or
  `{:error, atom}` on shape mismatch. The webhook controller hands
  this struct to `InboundIntake`.
  """
  @callback parse_inbound(payload :: map()) ::
              {:ok, InboundMessage.t()} | {:error, atom()}

  @doc """
  The canonical module-name string for the Phase 2 stub adapter.
  Use this in fixtures, demo seeds, and any code that needs to
  register a `Channel` row pointing at the stub.
  """
  @spec stub_module_string() :: String.t()
  def stub_module_string, do: Atom.to_string(@stub_module)
end
