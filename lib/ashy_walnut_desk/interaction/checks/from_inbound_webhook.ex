defmodule AshyWalnutDesk.Interaction.Checks.FromInboundWebhook do
  @moduledoc """
  Ash policy check matching changesets/queries carrying
  `context: %{from_inbound_webhook: true}`.

  Gates internal-only inbound-intake actions:
  - `Inbox.:record_inbound` — creates the chain entry from a
    webhook without an operator actor.
  - `Identity.:register_provisional` — auto-creates a placeholder
    Identity when an unknown sender hits the webhook.
  - `Message.:record_message` for `:inbound` direction.

  Without this check, those actions are operator-callable directly,
  which breaks the "Inbox is operator-initiated" invariant from
  Phase 2 and exposes the chain to forged intake. The system actor
  set in `Accounts.ensure_system_actor/0` is the only legitimate
  actor on these paths; this check is the gate.

  See ADR-024.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_inbound_webhook == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_inbound_webhook) == true
  end

  def match?(_actor, %{query: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_inbound_webhook) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
