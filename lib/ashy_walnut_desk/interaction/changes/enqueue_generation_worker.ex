defmodule AshyWalnutDesk.Interaction.Changes.EnqueueGenerationWorker do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.AI.Jobs.GenerationWorker

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, &enqueue/2)
  end

  defp enqueue(_changeset, draft) do
    args = %{"draft_id" => draft.id}

    case GenerationWorker.new(args, unique: [period: 60, keys: [:draft_id]])
         |> Oban.insert() do
      {:ok, _job} -> {:ok, draft}
      {:error, reason} -> {:error, reason}
    end
  end
end
