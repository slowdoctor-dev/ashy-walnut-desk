defmodule AshyWalnutDesk.Knowledge.Jobs.ChunkAndEmbedWorkerTest do
  @moduledoc """
  Story 5.3 AC3/AC4 — author/revise enqueue the indexing job; the
  worker stages + embeds chunks (Fixture embedder), reuses vectors for
  unchanged content hashes on re-index, prunes superseded revisions,
  and noops on stale jobs.
  """

  use AshyWalnutDesk.DataCase, async: false

  require Ash.Query

  import Ash.Expr

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, ManualChunk}

  defmodule CountingEmbedder do
    @moduledoc false
    @behaviour AshyWalnutDesk.Knowledge.Embedder

    @impl true
    def embed(texts, opts) do
      Process.put(:embed_calls, Process.get(:embed_calls, []) ++ [length(texts)])
      AshyWalnutDesk.Knowledge.Embedders.Fixture.embed(texts, opts)
    end
  end

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :embedding_adapter)
    prev_allowlist = Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist)

    Application.put_env(:ashy_walnut_desk, :embedding_adapter, CountingEmbedder)

    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter_allowlist,
      [CountingEmbedder | prev_allowlist]
    )

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :embedding_adapter, prev_adapter)
      Application.put_env(:ashy_walnut_desk, :embedding_adapter_allowlist, prev_allowlist)
    end)

    Process.put(:embed_calls, [])
    admin = AccountsFixtures.create_user(:admin)
    %{admin: admin}
  end

  defp chunks_for(manual_id) do
    ManualChunk
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(expr(manual_id == ^manual_id))
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp drain do
    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)
  end

  test "author enqueues; drain stages, embeds, and labels chunks", %{admin: admin} do
    body = "Alpha paragraph.\n\n" <> String.duplicate("b", 1_700)

    {:ok, manual} =
      Ash.create(
        Manual,
        %{title: "Index me", slug: "index-me", body: body},
        action: :author,
        actor: admin
      )

    assert %{success: 1} = drain()

    chunks = chunks_for(manual.id)
    assert length(chunks) >= 2
    assert Enum.map(chunks, & &1.position) == Enum.to_list(0..(length(chunks) - 1)//1)

    assert Enum.all?(chunks, &(&1.revision == 1))
    assert Enum.all?(chunks, &(&1.embedding != nil))
    assert Enum.all?(chunks, &(&1.embedder == inspect(CountingEmbedder)))
    assert Enum.all?(chunks, &(&1.embedded_at != nil))
  end

  test "revise re-indexes: new revision staged, stale pruned, unchanged vectors reused",
       %{admin: admin} do
    stable = String.duplicate("a", 1_000)
    original = String.duplicate("b", 1_000)
    replacement = String.duplicate("c", 1_000)

    {:ok, manual} =
      Ash.create(
        Manual,
        %{
          title: "Reindex",
          slug: "reindex-manual",
          body: stable <> "\n\n" <> original
        },
        action: :author,
        actor: admin
      )

    assert %{success: 1} = drain()
    assert Process.get(:embed_calls) == [2]

    {:ok, revised} =
      Ash.update(
        manual,
        %{body: stable <> "\n\n" <> replacement},
        action: :revise,
        actor: admin
      )

    assert revised.revision == 2
    Process.put(:embed_calls, [])

    assert %{success: 1} = drain()

    chunks = chunks_for(manual.id)
    assert Enum.all?(chunks, &(&1.revision == 2))
    assert Enum.all?(chunks, &(&1.embedding != nil))

    # Only the changed chunk needed a fresh embed; the unchanged one
    # reused its revision-1 vector by content hash.
    assert Process.get(:embed_calls) == [1]
  end

  test "stale job (older revision) noops", %{admin: admin} do
    {:ok, manual} =
      Ash.create(
        Manual,
        %{title: "Stale", slug: "stale-manual", body: "Original."},
        action: :author,
        actor: admin
      )

    {:ok, _revised} = Ash.update(manual, %{body: "Newer content."}, action: :revise, actor: admin)

    # Drain runs both jobs; the revision-1 job must not resurrect
    # revision-1 chunks after the revision-2 job ran.
    assert %{success: 2} = drain()

    chunks = chunks_for(manual.id)
    assert chunks != []
    assert Enum.all?(chunks, &(&1.revision == 2))
    assert Enum.map(chunks, & &1.content) == ["Newer content."]
  end

  test "job for a deleted manual noops", %{admin: admin} do
    {:ok, manual} =
      Ash.create(
        Manual,
        %{title: "Gone", slug: "gone-manual", body: "Body."},
        action: :author,
        actor: admin
      )

    {:ok, _} = Ash.update(manual, %{}, action: :soft_delete, actor: admin)

    assert %{success: 1} = drain()
    assert chunks_for(manual.id) == []
  end
end
