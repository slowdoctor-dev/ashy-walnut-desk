defmodule AshyWalnutDesk.Knowledge.ChunkerTest do
  @moduledoc """
  Story 5.3 AC1 — blank-line splitting, greedy merge to the size cap,
  hard wrap for oversized paragraphs, and the property invariants:
  coverage (no non-whitespace character lost), determinism, size cap,
  and correct SHA-256 content hashes.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshyWalnutDesk.Knowledge.Chunker

  defp squash_whitespace(text), do: String.replace(text, ~r/\s+/u, "")

  test "splits on blank lines and merges small paragraphs greedily" do
    body = "First paragraph.\n\nSecond paragraph.\n\n\nThird one."

    assert [%{position: 0, content: content}] = Chunker.chunk(body)
    assert content == "First paragraph.\n\nSecond paragraph.\n\nThird one."
  end

  test "keeps paragraphs apart when merging would exceed the cap" do
    a = String.duplicate("a", 1_000)
    b = String.duplicate("b", 1_000)

    assert [%{position: 0, content: ^a}, %{position: 1, content: ^b}] =
             Chunker.chunk(a <> "\n\n" <> b)
  end

  test "hard-wraps a single oversized paragraph" do
    oversized = String.duplicate("x", Chunker.max_chunk_chars() * 2 + 10)
    chunks = Chunker.chunk(oversized)

    assert length(chunks) == 3
    assert Enum.all?(chunks, &(String.length(&1.content) <= Chunker.max_chunk_chars()))
    assert squash_whitespace(Enum.map_join(chunks, "", & &1.content)) == oversized
  end

  test "content_hash is lowercase hex sha256 of the chunk content" do
    [%{content: content, content_hash: hash}] = Chunker.chunk("hash me")

    assert hash ==
             :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  test "empty and whitespace-only bodies produce no chunks" do
    assert Chunker.chunk("") == []
    assert Chunker.chunk("  \n\n  \n") == []
  end

  property "coverage, determinism, cap, and positional order hold for arbitrary bodies" do
    check all(
            paragraphs <-
              StreamData.list_of(
                StreamData.string(:printable, min_length: 0, max_length: 400),
                max_length: 12
              ),
            max_runs: 40
          ) do
      body = Enum.join(paragraphs, "\n\n")
      chunks = Chunker.chunk(body)

      # Determinism
      assert chunks == Chunker.chunk(body)

      # Coverage: no non-whitespace content lost or invented
      joined = Enum.map_join(chunks, "", & &1.content)
      assert squash_whitespace(joined) == squash_whitespace(body)

      # Size cap + contiguous positions + hash integrity
      assert Enum.all?(chunks, &(String.length(&1.content) <= Chunker.max_chunk_chars()))
      assert Enum.map(chunks, & &1.position) == Enum.to_list(0..(length(chunks) - 1)//1)
      assert Enum.all?(chunks, &(&1.content_hash == Chunker.content_hash(&1.content)))
    end
  end
end
