defmodule AshyWalnutDesk.Knowledge.Checks.FromIndexingWorker do
  @moduledoc """
  Ash policy check matching changesets carrying
  `context: %{from_indexing_worker: true}`.

  Gates the ManualChunk lifecycle actions (`:stage`,
  `:stamp_embedding`, `:prune`) to `Jobs.ChunkAndEmbedWorker` — chunk
  rows are derived data; no operator/admin path writes them directly.
  Mirrors `Interaction.Checks.FromGenerationWorker`.
  """

  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "context.from_indexing_worker == true"

  @impl true
  def match?(_actor, %{changeset: %{context: context}}, _opts) when is_map(context) do
    Map.get(context, :from_indexing_worker) == true
  end

  def match?(_actor, _subject, _opts), do: false
end
