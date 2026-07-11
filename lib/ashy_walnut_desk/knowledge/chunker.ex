defmodule AshyWalnutDesk.Knowledge.Chunker do
  @moduledoc """
  Pure Manual-body chunker (story 5.3): split on blank lines,
  greedy-merge adjacent paragraphs up to 1,600 characters, hard-wrap
  oversized paragraphs. Deterministic; every non-whitespace character of
  the input appears in exactly one chunk (property-tested invariant).
  """

  @max_chunk_chars 1_600

  @type chunk :: %{position: non_neg_integer(), content: String.t(), content_hash: String.t()}

  @spec max_chunk_chars() :: pos_integer()
  def max_chunk_chars, do: @max_chunk_chars

  @spec chunk(String.t()) :: [chunk()]
  def chunk(body) when is_binary(body) do
    body
    |> String.split(~r/\n\s*\n/u, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(&hard_wrap/1)
    |> greedy_merge()
    |> Enum.with_index()
    |> Enum.map(fn {content, position} ->
      %{position: position, content: content, content_hash: content_hash(content)}
    end)
  end

  @spec content_hash(String.t()) :: String.t()
  def content_hash(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp hard_wrap(paragraph) do
    if String.length(paragraph) <= @max_chunk_chars do
      [paragraph]
    else
      paragraph
      |> String.graphemes()
      |> Enum.chunk_every(@max_chunk_chars)
      |> Enum.map(&Enum.join/1)
    end
  end

  defp greedy_merge(paragraphs) do
    paragraphs
    |> Enum.reduce([], &merge_step/2)
    |> Enum.reverse()
  end

  defp merge_step(paragraph, []), do: [paragraph]

  defp merge_step(paragraph, [current | rest]) do
    merged = current <> "\n\n" <> paragraph

    if String.length(merged) <= @max_chunk_chars do
      [merged | rest]
    else
      [paragraph, current | rest]
    end
  end
end
