defmodule AshyWalnutDesk.Interaction.Checks.FromActionWorker do
  @moduledoc """
  Ash policy check matching changesets carrying
  `context: %{from_action_worker: true}`.

  Gates the internal-only worker-driven transitions on `Action`:

  - `Action.:complete_outbound` — adapter succeeded; worker writes
    the executed state + outbound `Message` + Inbox transition.
  - `Action.:fail_outbound` — adapter failed permanently or retries
    were exhausted; worker stamps the terminal failure.

  Without this gate, an operator could `Ash.update(action, ...,
  action: :complete_outbound)` directly and mark a never-sent
  `Action` as `:executed`. The Oban worker (`Jobs.OutboundSend`) is
  the only legitimate caller of these actions and sets the flag.

  See ADR-023 and `specs/phase-3/architecture.md §3.5`.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_action_worker == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_action_worker) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
