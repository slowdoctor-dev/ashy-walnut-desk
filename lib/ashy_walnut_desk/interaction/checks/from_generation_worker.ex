defmodule AshyWalnutDesk.Interaction.Checks.FromGenerationWorker do
  @moduledoc """
  Ash policy check matching changesets carrying
  `context: %{from_generation_worker: true}`.

  Gates internal worker-driven Draft transitions:

  - `Draft.:complete_generation`
  - `Draft.:fail_generation`
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_generation_worker == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_generation_worker) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
