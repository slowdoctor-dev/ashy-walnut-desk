defmodule AshyWalnutDesk.Knowledge.Jobs.ChunkAndEmbedWorker do
  @moduledoc """
  Oban worker (queue `:knowledge_indexing`, story 5.3): turns a Manual
  revision into staged + embedded ManualChunk rows.

  Pipeline per architecture §4.2: stale-job noop → chunk → stage
  (idempotent by `(revision, position)`) → reuse vectors for unchanged
  `content_hash` → embed the rest via the configured Embedder → prune
  superseded revisions.

  Failure semantics: `:transient`/`:rate_limited`/`:timeout` raise so
  Oban retries; `:permanent` leaves rows staged-but-unembedded (the
  lexical fallback still serves them) and the job succeeds;
  `:not_configured` (EMBEDDING_ADAPTER=none) skips embedding entirely.
  """

  use Oban.Worker, queue: :knowledge_indexing, max_attempts: 5

  require Ash.Query
  require Logger

  import Ash.Expr

  alias AshyWalnutDesk.Knowledge.{Chunker, Embedder, Manual, ManualChunk}
  alias AshyWalnutDesk.Knowledge.Embedders

  @worker_context %{from_indexing_worker: true}

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) when attempt > 0 do
    round(:math.pow(2, attempt - 1) * 30)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"manual_id" => manual_id, "revision" => revision}}) do
    case load_manual(manual_id) do
      {:ok, %Manual{revision: ^revision} = manual} -> index(manual)
      {:ok, _newer_revision_exists} -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{args: args}) do
    arg_keys = if is_map(args), do: Map.keys(args), else: []
    Logger.error("ChunkAndEmbedWorker: unrecognized job args keys=#{inspect(arg_keys)}")
    {:error, :unrecognized_job_args}
  end

  defp load_manual(manual_id) do
    case Ash.get(Manual, manual_id, authorize?: false) do
      {:ok, manual} -> {:ok, manual}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :not_found}
      {:error, %Ash.Error.Invalid{}} -> {:error, :not_found}
      other -> other
    end
  end

  defp index(manual) do
    start = System.monotonic_time()
    chunks = Chunker.chunk(manual.body)
    existing = existing_chunks(manual.id)

    embedded_by_hash =
      existing
      |> Enum.filter(&(&1.embedding != nil))
      |> Map.new(&{&1.content_hash, &1})

    current_by_position =
      existing
      |> Enum.filter(&(&1.revision == manual.revision))
      |> Map.new(&{&1.position, &1})

    rows = Enum.map(chunks, &ensure_staged(manual, &1, current_by_position))

    {reusable, to_embed} =
      rows
      |> Enum.filter(&is_nil(&1.embedding))
      |> Enum.split_with(&Map.has_key?(embedded_by_hash, &1.content_hash))

    Enum.each(reusable, fn row ->
      source = Map.fetch!(embedded_by_hash, row.content_hash)
      stamp!(row, source.embedding, source.embedder)
    end)

    result = embed_rows(to_embed)
    prune_stale!(existing, manual.revision)

    :telemetry.execute(
      [:awd, :knowledge, :indexing, :stop],
      %{
        duration: System.monotonic_time() - start,
        chunk_count: length(rows),
        embedded_count: length(reusable) + length(to_embed) - length(result.skipped)
      },
      %{manual_id: manual.id, revision: manual.revision, outcome: result.outcome}
    )

    :ok
  end

  defp existing_chunks(manual_id) do
    ManualChunk
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(expr(manual_id == ^manual_id))
    |> Ash.read!(authorize?: false)
  end

  # Idempotent staging: a retry after a partial failure finds the row
  # for (revision, position) already present and reuses it.
  defp ensure_staged(manual, chunk, current_by_position) do
    case Map.get(current_by_position, chunk.position) do
      %ManualChunk{content_hash: hash} = row when hash == chunk.content_hash ->
        row

      _missing_or_changed ->
        Ash.create!(
          ManualChunk,
          %{
            manual_id: manual.id,
            revision: manual.revision,
            position: chunk.position,
            content: chunk.content,
            content_hash: chunk.content_hash
          },
          action: :stage,
          authorize?: false,
          context: @worker_context
        )
    end
  end

  defp embed_rows([]), do: %{outcome: :nothing_to_embed, skipped: []}

  defp embed_rows(rows) do
    case Embedder.resolve() do
      {:ok, embedder} ->
        embed_with(embedder, rows)

      {:error, :not_configured} ->
        %{outcome: :embedding_skipped, skipped: rows}

      {:error, {:embedder_not_allowed, module}} ->
        raise "embedder not allowed: #{inspect(module)}"
    end
  end

  defp embed_with(embedder, rows) do
    contents = Enum.map(rows, & &1.content)

    case embedder.embed(contents, input_type: "document") do
      {:ok, vectors} ->
        rows
        |> Enum.zip(vectors)
        |> Enum.each(fn {row, vector} -> stamp!(row, vector, embedder_label(embedder)) end)

        %{outcome: :embedded, skipped: []}

      {:error, :permanent} ->
        Logger.warning("ChunkAndEmbedWorker: permanent embed failure; leaving rows unembedded")
        %{outcome: :embed_failed_permanent, skipped: rows}

      {:error, reason} ->
        raise "embedding failed (#{inspect(reason)})"
    end
  end

  defp stamp!(row, vector, label) do
    Ash.update!(
      row,
      %{embedding: vector, embedder: label},
      action: :stamp_embedding,
      authorize?: false,
      context: @worker_context
    )
  end

  defp prune_stale!(existing, current_revision) do
    existing
    |> Enum.filter(&(&1.revision != current_revision))
    |> Enum.each(fn row ->
      Ash.destroy!(row, action: :prune, authorize?: false, context: @worker_context)
    end)
  end

  defp embedder_label(Embedders.Fixture), do: "fixture"

  defp embedder_label(Embedders.Voyage) do
    "voyage:" <> Application.get_env(:ashy_walnut_desk, :embedding_model, "voyage-3.5-lite")
  end

  defp embedder_label(module), do: inspect(module)
end
