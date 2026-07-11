defmodule AshyWalnutDesk.Knowledge.ManualChunkTest do
  @moduledoc """
  Story 5.3 AC2 — ManualChunk lifecycle actions are worker-gated
  (`FromIndexingWorker` context), reads are admin-only, and the
  `(manual_id, revision, position)` uniqueness holds.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Chunker, Manual, ManualChunk}
  alias AshyWalnutDesk.Knowledge.Embedders.Fixture

  @worker_context %{from_indexing_worker: true}

  defp author_manual!(admin) do
    Ash.create!(
      Manual,
      %{
        title: "Chunk host",
        slug: "chunk-host-#{System.unique_integer([:positive])}",
        body: "Some knowledge body."
      },
      action: :author,
      actor: admin
    )
  end

  defp stage!(manual, position, content) do
    Ash.create!(
      ManualChunk,
      %{
        manual_id: manual.id,
        revision: manual.revision,
        position: position,
        content: content,
        content_hash: Chunker.content_hash(content)
      },
      action: :stage,
      authorize?: false,
      context: @worker_context
    )
  end

  test "stage/stamp_embedding/prune are refused for admin and operator actors" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    manual = author_manual!(admin)

    attrs = %{
      manual_id: manual.id,
      revision: manual.revision,
      position: 0,
      content: "nope",
      content_hash: String.duplicate("0", 64)
    }

    for actor <- [admin, operator] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.create(ManualChunk, attrs, action: :stage, actor: actor)
    end

    chunk = stage!(manual, 0, "worker staged")

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(chunk, %{embedding: List.duplicate(0.0, 1024), embedder: "fixture"},
               action: :stamp_embedding,
               actor: admin
             )

    assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(chunk, action: :prune, actor: admin)
  end

  test "worker context can stage, stamp, and prune; stamp sets embedded_at" do
    admin = AccountsFixtures.create_user(:admin)
    manual = author_manual!(admin)

    chunk = stage!(manual, 0, "embed me")
    assert is_nil(chunk.embedding)
    assert is_nil(chunk.embedded_at)

    {:ok, [vector]} = Fixture.embed(["embed me"])

    stamped =
      Ash.update!(
        chunk,
        %{embedding: vector, embedder: "fixture"},
        action: :stamp_embedding,
        authorize?: false,
        context: @worker_context
      )

    refute is_nil(stamped.embedding)
    assert stamped.embedder == "fixture"
    refute is_nil(stamped.embedded_at)

    assert :ok =
             Ash.destroy!(stamped, action: :prune, authorize?: false, context: @worker_context)
  end

  test "duplicate (manual_id, revision, position) is rejected" do
    admin = AccountsFixtures.create_user(:admin)
    manual = author_manual!(admin)

    stage!(manual, 0, "first")

    assert_raise Ash.Error.Invalid, fn -> stage!(manual, 0, "second") end
  end

  test "reads are admin-only" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    manual = author_manual!(admin)
    stage!(manual, 0, "visible to admin")

    assert {:ok, rows} = Ash.read(ManualChunk, actor: admin)
    assert length(rows) == 1

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(ManualChunk, actor: operator)
  end
end
