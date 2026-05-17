defmodule AshyWalnutDesk.Interaction.Checks.FromDraftApprove do
  @moduledoc """
  Ash policy check: matches when the changeset/query carries
  `context: %{from_draft_approve: true}`.

  Used to gate internal-only actions like `Action.:register_pending`
  and `Compensation.:register`, which must only be callable from
  within `Draft.:approve`'s `CompensationAtApproval` change. Without
  this check, those actions are operator-callable directly — which
  breaks ADR-016's four-stage chain invariant (Action without
  Compensation, or Compensation without provenance from a real
  Draft approval).
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_draft_approve == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_draft_approve) == true
  end

  def match?(_actor, %{query: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_draft_approve) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
