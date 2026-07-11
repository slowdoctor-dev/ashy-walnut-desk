defmodule AshyWalnutDesk.Knowledge.RetrieverTest do
  @moduledoc """
  Story 5.4 AC1 — the ladder never raises and never returns
  `{:error, _}`: disabled config, blank/nil queries, empty index,
  missing adapter, and raising embedders all degrade to a
  `%RetrievalResult{}`.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, RetrievalResult, Retriever}

  defmodule RaisingEmbedder do
    @moduledoc false
    @behaviour AshyWalnutDesk.Knowledge.Embedder
    @impl true
    def embed(_texts, _opts), do: raise("boom")
  end

  setup do
    prev = %{
      retrieval: Application.get_env(:ashy_walnut_desk, :retrieval),
      adapter: Application.get_env(:ashy_walnut_desk, :embedding_adapter),
      allowlist: Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist)
    }

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :retrieval, prev.retrieval)
      Application.put_env(:ashy_walnut_desk, :embedding_adapter, prev.adapter)
      Application.put_env(:ashy_walnut_desk, :embedding_adapter_allowlist, prev.allowlist)
    end)

    %{prev: prev}
  end

  defp author_and_index!(slug, body) do
    admin = AccountsFixtures.create_user(:admin)

    manual =
      Ash.create!(
        Manual,
        %{title: "Retriever host", slug: slug, body: body},
        action: :author,
        actor: admin
      )

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)
    manual
  end

  test "retrieval disabled → mode :none" do
    Application.put_env(:ashy_walnut_desk, :retrieval, enabled?: false)

    assert {:ok, %RetrievalResult{mode: :none, excerpts: []}} =
             Retriever.retrieve("anything at all")
  end

  test "blank and nil queries → mode :none" do
    assert {:ok, %RetrievalResult{mode: :none}} = Retriever.retrieve("   ")
    assert {:ok, %RetrievalResult{mode: :none}} = Retriever.retrieve(nil)
  end

  test "empty index → mode :none (vector under-populated, lexical empty)" do
    assert {:ok, %RetrievalResult{mode: :none, excerpts: []}} =
             Retriever.retrieve("scheduling policy")
  end

  test "no embedding adapter (none posture) falls to lexical over staged chunks" do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, nil)
    author_and_index!("lexical-only", "Scheduling policy: confirm the requested time.")

    assert {:ok, %RetrievalResult{mode: :lexical, excerpts: [excerpt]}} =
             Retriever.retrieve("scheduling policy confirm")

    assert excerpt.manual_slug == "lexical-only"
    assert is_nil(excerpt.score)
  end

  test "raising embedder degrades to lexical, never raises", %{prev: prev} do
    author_and_index!("raise-lane", "Scheduling policy: confirm the requested time.")

    Application.put_env(:ashy_walnut_desk, :embedding_adapter, RaisingEmbedder)

    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter_allowlist,
      [RaisingEmbedder | prev.allowlist]
    )

    assert {:ok, %RetrievalResult{mode: :lexical, excerpts: [excerpt]}} =
             Retriever.retrieve("scheduling policy confirm")

    assert excerpt.manual_slug == "raise-lane"
  end
end
