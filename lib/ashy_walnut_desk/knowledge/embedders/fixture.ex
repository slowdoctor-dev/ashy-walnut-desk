defmodule AshyWalnutDesk.Knowledge.Embedders.Fixture do
  @moduledoc """
  Deterministic offline embedder for tests and local development
  (ADR-026): hashed bag-of-words → L2-normalized vector.

  Tokens hash into dimension buckets (`:erlang.phash2/2`) with count
  weighting, so overlapping texts share buckets and rank closer under
  cosine similarity than disjoint texts — structural similarity, not
  semantic, but stable and meaningful enough for ranking assertions.
  """

  @behaviour AshyWalnutDesk.Knowledge.Embedder

  alias AshyWalnutDesk.Knowledge.Embedder

  @impl true
  def embed(texts, opts \\ []) when is_list(texts) do
    dimension = opts[:dimension] || Embedder.dimension()
    {:ok, Enum.map(texts, &vectorize(&1, dimension))}
  end

  defp vectorize(text, dimension) do
    counts =
      text
      |> String.downcase()
      |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
      |> Enum.reduce(%{}, fn token, acc ->
        Map.update(acc, :erlang.phash2(token, dimension), 1.0, &(&1 + 1.0))
      end)

    norm =
      counts
      |> Map.values()
      |> Enum.reduce(0.0, fn weight, acc -> acc + weight * weight end)
      |> :math.sqrt()

    if norm == 0.0 do
      # Empty/whitespace text: a fixed unit vector keeps cosine defined.
      [1.0 | List.duplicate(0.0, dimension - 1)]
    else
      for bucket <- 0..(dimension - 1), do: Map.get(counts, bucket, 0.0) / norm
    end
  end
end
