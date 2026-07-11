defmodule AshyWalnutDesk.Knowledge.RetrieverVectorTest do
  @moduledoc """
  Story 5.4 AC2 — the vector rung ranks by cosine similarity under the
  deterministic Fixture embedder, honors `top_k`/`min_score`/
  `token_budget`, and carries full provenance on each excerpt.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, RetrievalResult, Retriever}

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :retrieval)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :retrieval, prev) end)

    admin = AccountsFixtures.create_user(:admin)
    %{admin: admin}
  end

  defp author_and_index!(admin, slug, body) do
    manual =
      Ash.create!(
        Manual,
        %{title: slug, slug: slug, body: body},
        action: :author,
        actor: admin
      )

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)
    manual
  end

  test "related content wins; unrelated content falls under min_score", %{admin: admin} do
    related =
      author_and_index!(
        admin,
        "scheduling-manual",
        "Appointment scheduling policy: confirm requested time with the client."
      )

    _unrelated =
      author_and_index!(
        admin,
        "billing-manual",
        "Billing refunds ledger reconciliation quarterly totals."
      )

    assert {:ok, %RetrievalResult{mode: :vector, excerpts: [excerpt]}} =
             Retriever.retrieve("appointment scheduling policy confirm requested time client")

    assert excerpt.manual_id == related.id
    assert excerpt.manual_slug == "scheduling-manual"
    assert excerpt.revision == 1
    assert excerpt.position == 0
    assert is_binary(excerpt.content_hash)
    assert excerpt.embedder == "fixture"
    assert excerpt.score > 0.5
  end

  test "top_k bounds the result set", %{admin: admin} do
    for n <- 1..3 do
      author_and_index!(
        admin,
        "scheduling-#{n}",
        "Appointment scheduling policy variant #{n}: confirm requested time."
      )
    end

    Application.put_env(
      :ashy_walnut_desk,
      :retrieval,
      enabled?: true,
      top_k: 2,
      min_score: 0.3,
      token_budget: 1_200
    )

    assert {:ok, %RetrievalResult{mode: :vector, excerpts: excerpts}} =
             Retriever.retrieve("appointment scheduling policy confirm requested time")

    assert length(excerpts) == 2
  end

  test "token_budget trims the tail", %{admin: admin} do
    for n <- 1..2 do
      author_and_index!(
        admin,
        "budget-#{n}",
        "Appointment scheduling policy variant #{n}: confirm requested time." <>
          String.duplicate(" filler", 40)
      )
    end

    Application.put_env(
      :ashy_walnut_desk,
      :retrieval,
      # Each chunk is ~350 chars ≈ 87 tokens; budget of 100 keeps one.
      enabled?: true,
      top_k: 4,
      min_score: 0.2,
      token_budget: 100
    )

    assert {:ok, %RetrievalResult{mode: :vector, excerpts: excerpts}} =
             Retriever.retrieve("appointment scheduling policy confirm requested time filler")

    assert length(excerpts) == 1
  end
end
