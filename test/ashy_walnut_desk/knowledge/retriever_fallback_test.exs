defmodule AshyWalnutDesk.Knowledge.RetrieverFallbackTest do
  @moduledoc """
  Story 5.4 AC3 — the lexical rung serves staged-unembedded chunks via
  pg_trgm when the embedder fails or is absent, records
  `mode: :lexical`, and ranks by trigram similarity.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, RetrievalResult, Retriever}

  defmodule FailingEmbedder do
    @moduledoc false
    @behaviour AshyWalnutDesk.Knowledge.Embedder
    @impl true
    def embed(_texts, _opts), do: {:error, :timeout}
  end

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :embedding_adapter)
    prev_allowlist = Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist)

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :embedding_adapter, prev_adapter)
      Application.put_env(:ashy_walnut_desk, :embedding_adapter_allowlist, prev_allowlist)
    end)

    %{admin: AccountsFixtures.create_user(:admin), prev_allowlist: prev_allowlist}
  end

  defp author_and_index!(admin, slug, body) do
    manual =
      Ash.create!(Manual, %{title: slug, slug: slug, body: body}, action: :author, actor: admin)

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)
    manual
  end

  test "unembedded chunks (none posture at index time) are lexically retrievable",
       %{admin: admin} do
    Application.put_env(:ashy_walnut_desk, :embedding_adapter, nil)

    author_and_index!(admin, "trgm-a", "Refund handling procedure for cancelled bookings.")
    author_and_index!(admin, "trgm-b", "Completely different waffle recipe collection.")

    assert {:ok, %RetrievalResult{mode: :lexical, excerpts: excerpts}} =
             Retriever.retrieve("refund handling procedure cancelled")

    assert [%{manual_slug: "trgm-a"} | _] = excerpts
    assert Enum.all?(excerpts, &is_nil(&1.score))
  end

  test "query-time embedder error degrades embedded index to lexical",
       %{admin: admin, prev_allowlist: prev_allowlist} do
    author_and_index!(admin, "degrade-lane", "Refund handling procedure for cancelled bookings.")

    Application.put_env(:ashy_walnut_desk, :embedding_adapter, FailingEmbedder)

    Application.put_env(
      :ashy_walnut_desk,
      :embedding_adapter_allowlist,
      [FailingEmbedder | prev_allowlist]
    )

    assert {:ok, %RetrievalResult{mode: :lexical, excerpts: [excerpt]}} =
             Retriever.retrieve("refund handling procedure cancelled")

    assert excerpt.manual_slug == "degrade-lane"
  end
end
