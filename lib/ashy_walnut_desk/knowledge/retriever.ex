defmodule AshyWalnutDesk.Knowledge.Retriever do
  @moduledoc """
  Never-raising retrieval ladder (story 5.4, architecture §4.1):

  1. retrieval disabled or blank query        → `mode: :none`
  2. embed query via the configured Embedder
     → pgvector cosine top-k over active manuals' current revisions
     → `mode: :vector`
  3. embedder missing/failing, or vector rung under-populated
     → pg_trgm lexical top-k                  → `mode: :lexical`
  4. nothing matched anywhere                 → `mode: :none`

  Every failure class degrades one rung — `retrieve/2` always returns
  `{:ok, %RetrievalResult{}}` so a retrieval outage can never fail a
  generation. Scope filters at every rung: manual `:active`, not
  soft-deleted, chunk revision current.
  """

  require Ash.Query
  require Ash.Sort
  require Logger

  import Ash.Expr

  alias AshyWalnutDesk.Knowledge.{Embedder, ManualChunk, RetrievalResult}

  @query_char_limit 2_000
  @defaults [enabled?: true, top_k: 4, min_score: 0.5, token_budget: 1_200]

  @spec retrieve(String.t() | nil, keyword()) :: {:ok, RetrievalResult.t()}
  def retrieve(query_text, opts \\ [])

  def retrieve(query_text, opts) when is_binary(query_text) do
    config = config()
    start = System.monotonic_time()
    bounded = bound_query(query_text)

    result =
      cond do
        !Keyword.get(config, :enabled?, true) -> %RetrievalResult{mode: :none}
        String.trim(bounded) == "" -> %RetrievalResult{mode: :none}
        true -> vector_rung(bounded, config)
      end

    :telemetry.execute(
      [:awd, :knowledge, :retrieval, :stop],
      %{duration: System.monotonic_time() - start, chunk_count: length(result.excerpts)},
      %{mode: result.mode, draft_id: opts[:draft_id]}
    )

    {:ok, result}
  end

  def retrieve(_query_text, _opts), do: {:ok, %RetrievalResult{mode: :none}}

  # ── Rung 2: vector ────────────────────────────────────────────────

  defp vector_rung(query_text, config) do
    with {:ok, embedder} <- Embedder.resolve(),
         {:ok, [query_vector]} <- safe_embed(embedder, query_text),
         [_ | _] = excerpts <- vector_search(query_vector, config) do
      %RetrievalResult{mode: :vector, excerpts: excerpts}
    else
      _fall_through -> lexical_rung(query_text, config)
    end
  end

  defp safe_embed(embedder, text) do
    embedder.embed([text], input_type: "query")
  rescue
    error ->
      Logger.warning("Retriever: query embed raised #{inspect(error.__struct__)}")
      {:error, :embed_raised}
  end

  defp vector_search(query_vector, config) do
    max_distance = 1.0 - Keyword.fetch!(config, :min_score)

    scoped_chunks()
    |> Ash.Query.filter(expr(not is_nil(embedding)))
    |> Ash.Query.filter(expr(vector_cosine_distance(embedding, ^query_vector) <= ^max_distance))
    |> Ash.Query.sort([
      {Ash.Sort.expr_sort(vector_cosine_distance(embedding, ^query_vector), :float), :asc}
    ])
    |> Ash.Query.limit(Keyword.fetch!(config, :top_k))
    |> Ash.read!(authorize?: false)
    |> Enum.map(&to_excerpt(&1, cosine_score(&1.embedding, query_vector)))
    |> apply_token_budget(config)
  rescue
    error ->
      Logger.warning("Retriever: vector search failed (#{inspect(error.__struct__)})")
      []
  end

  # ── Rung 3: lexical (pg_trgm) ─────────────────────────────────────

  defp lexical_rung(query_text, config) do
    case lexical_search(query_text, config) do
      [] -> %RetrievalResult{mode: :none}
      excerpts -> %RetrievalResult{mode: :lexical, excerpts: excerpts}
    end
  end

  defp lexical_search(query_text, config) do
    scoped_chunks()
    |> Ash.Query.filter(expr(trigram_similarity(content, ^query_text) > 0.0))
    |> Ash.Query.sort([
      {Ash.Sort.expr_sort(trigram_similarity(content, ^query_text), :float), :desc}
    ])
    |> Ash.Query.limit(Keyword.fetch!(config, :top_k))
    |> Ash.read!(authorize?: false)
    |> Enum.map(&to_excerpt(&1, nil))
    |> apply_token_budget(config)
  rescue
    error ->
      Logger.warning("Retriever: lexical search failed (#{inspect(error.__struct__)})")
      []
  end

  # ── Shared scope + shaping ────────────────────────────────────────

  defp scoped_chunks do
    ManualChunk
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(
      expr(manual.status == :active and is_nil(manual.deleted_at) and revision == manual.revision)
    )
    |> Ash.Query.load(:manual)
  end

  defp to_excerpt(chunk, score) do
    %{
      manual_id: chunk.manual_id,
      manual_slug: chunk.manual.slug,
      revision: chunk.revision,
      position: chunk.position,
      content: chunk.content,
      content_hash: chunk.content_hash,
      score: score,
      embedder: chunk.embedder
    }
  end

  defp apply_token_budget(excerpts, config) do
    budget = Keyword.fetch!(config, :token_budget)

    {kept, _spent} =
      Enum.reduce(excerpts, {[], 0}, fn excerpt, {kept, spent} ->
        cost = estimate_tokens(excerpt.content)

        if spent + cost <= budget do
          {[excerpt | kept], spent + cost}
        else
          {kept, spent}
        end
      end)

    Enum.reverse(kept)
  end

  defp estimate_tokens(text), do: max(1, div(String.length(text), 4))

  defp cosine_score(embedding, query_vector) do
    stored = to_float_list(embedding)
    query = to_float_list(query_vector)

    dot = Enum.zip(stored, query) |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
    norm_product = l2_norm(stored) * l2_norm(query)

    if norm_product == 0.0, do: 0.0, else: dot / norm_product
  end

  defp l2_norm(vector) do
    vector |> Enum.reduce(0.0, fn x, acc -> acc + x * x end) |> :math.sqrt()
  end

  defp to_float_list(%Ash.Vector{} = vector), do: Ash.Vector.to_list(vector)
  defp to_float_list(list) when is_list(list), do: list

  defp bound_query(query_text), do: String.slice(query_text, 0, @query_char_limit)

  defp config do
    Keyword.merge(@defaults, Application.get_env(:ashy_walnut_desk, :retrieval, []))
  end
end
