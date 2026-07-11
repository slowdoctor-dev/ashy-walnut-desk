defmodule AshyWalnutDesk.Knowledge.Changes.EnqueueIndexing do
  @moduledoc false

  use Ash.Resource.Change

  alias Ash.Changeset
  alias AshyWalnutDesk.Knowledge.Jobs.ChunkAndEmbedWorker

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, &enqueue/2)
  end

  defp enqueue(_changeset, manual) do
    args = %{"manual_id" => manual.id, "revision" => manual.revision}

    case ChunkAndEmbedWorker.new(args, unique: [period: 60, keys: [:manual_id, :revision]])
         |> Oban.insert() do
      {:ok, _job} -> {:ok, manual}
      {:error, reason} -> {:error, reason}
    end
  end
end
