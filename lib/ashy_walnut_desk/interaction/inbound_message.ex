defmodule AshyWalnutDesk.Interaction.InboundMessage do
  @moduledoc """
  Canonical shape returned by `Adapter.parse_inbound/1`. The webhook
  controller passes this struct (not the raw provider payload) into
  `InboundIntake`, so the inbound chain doesn't have to know which
  provider it came from.

  Phase 3 introduces this contract; future providers (WhatsApp,
  Line, KakaoTalk in Phase 6+) lift their format into this struct
  in their own `parse_inbound/1` implementation.

  See `specs/phase-3/architecture.md §3.1, §6.2` and ADR-022.
  """

  @type t :: %__MODULE__{
          provider: atom(),
          provider_message_id: String.t(),
          from: String.t(),
          to: String.t(),
          body: String.t(),
          received_at: DateTime.t()
        }

  @enforce_keys [:provider, :provider_message_id, :from, :to, :body, :received_at]
  defstruct [:provider, :provider_message_id, :from, :to, :body, :received_at]
end
