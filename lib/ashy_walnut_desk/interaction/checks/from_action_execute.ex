defmodule AshyWalnutDesk.Interaction.Checks.FromActionExecute do
  @moduledoc """
  Ash policy check: matches when the changeset/query carries
  `context: %{from_action_execute: true}`.

  Used to gate internal-only transitions like
  `Inbox.:mark_executed` and `Message.:record_message` for outbound
  rows, which must only fire from inside `Action.:execute`'s
  workflow. Without this check, the state machine is operator-
  bypassable: an operator could mark an Inbox `:executed` without
  going through the chain, or record an outbound Message without
  approver attribution.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_action_execute == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_action_execute) == true
  end

  def match?(_actor, %{query: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_action_execute) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
