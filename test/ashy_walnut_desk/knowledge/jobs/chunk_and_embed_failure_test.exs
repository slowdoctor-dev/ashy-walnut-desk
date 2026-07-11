defmodule AshyWalnutDesk.Knowledge.Jobs.ChunkAndEmbedFailureTest do
  @moduledoc """
  Story 5.3 AC4 — embed failure semantics: `:permanent` leaves rows
  staged-but-unembedded (lexical-servable) with a successful job;
  transient classes raise so Oban retries; the `:not_configured`
  posture (EMBEDDING_ADAPTER=none) skips embedding entirely.
  """

  use AshyWalnutDesk.DataCase, async: false

  require Ash.Query

  import Ash.Expr

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, ManualChunk}

  defmodule PermanentEmbedder do
    @moduledoc false
    @behaviour AshyWalnutDesk.Knowledge.Embedder
    @impl true
    def embed(_texts, _opts), do: {:error, :permanent}
  end

  defmodule TransientEmbedder do
    @moduledoc false
    @behaviour AshyWalnutDesk.Knowledge.Embedder
    @impl true
    def embed(_texts, _opts), do: {:error, :rate_limited}
  end

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :embedding_adapter)
    prev_allowlist = Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist)

    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter_allowlist,
      [PermanentEmbedder, TransientEmbedder | prev_allowlist]
    )

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :embedding_adapter, prev_adapter)
      Application.put_env(:ashy_walnut_desk, :embedding_adapter_allowlist, prev_allowlist)
    end)

    %{admin: AccountsFixtures.create_user(:admin)}
  end

  defp author!(admin, slug) do
    Ash.create!(
      Manual,
      %{title: "Failure lane", slug: slug, body: "Chunked but maybe unembedded."},
      action: :author,
      actor: admin
    )
  end

  defp chunks_for(manual_id) do
    ManualChunk
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(expr(manual_id == ^manual_id))
    |> Ash.read!(authorize?: false)
  end

  test "permanent embed failure: job succeeds, chunks stay unembedded", %{admin: admin} do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, PermanentEmbedder)
    manual = author!(admin, "permanent-failure")

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    assert [chunk] = chunks_for(manual.id)
    assert chunk.content == "Chunked but maybe unembedded."
    assert is_nil(chunk.embedding)
    assert is_nil(chunk.embedded_at)
  end

  test "transient embed failure: job raises and is retryable", %{admin: admin} do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, TransientEmbedder)
    manual = author!(admin, "transient-failure")

    assert %{failure: 1} =
             Oban.drain_queue(
               queue: :knowledge_indexing,
               with_recursion: true,
               with_safety: true
             )

    # Chunks are staged (the stage step committed) but not embedded.
    assert [chunk] = chunks_for(manual.id)
    assert is_nil(chunk.embedding)
  end

  test "EMBEDDING_ADAPTER=none posture: embedding skipped, job succeeds", %{admin: admin} do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, nil)
    manual = author!(admin, "none-posture")

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    assert [chunk] = chunks_for(manual.id)
    assert is_nil(chunk.embedding)
    assert is_nil(chunk.embedder)
  end
end
