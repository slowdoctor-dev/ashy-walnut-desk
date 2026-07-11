defmodule AshyWalnutDesk.Knowledge.Properties.RetrievalScopeTest do
  @moduledoc """
  Story 5.4 AC4 — scope invariant: whatever the population of manuals
  (active, archived, soft-deleted, revised), retrieval never serves an
  excerpt from an archived or deleted manual, and never from a stale
  revision.

  All `check all` iterations share one sandbox transaction, so manuals
  accumulate across iterations; the allowed/revised sets are tracked
  across the whole run (same pattern as the Phase 1 soft-delete
  property suite).
  """

  use AshyWalnutDesk.DataCase, async: false
  use ExUnitProperties

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.{Manual, Retriever}

  setup do
    Process.put(:scope_population, [])
    %{admin: AccountsFixtures.create_user(:admin)}
  end

  property "excerpts only ever come from active manuals' current revisions", %{admin: admin} do
    check all(
            fates <-
              StreamData.list_of(
                StreamData.member_of([:keep, :archive, :soft_delete, :revise]),
                min_length: 1,
                max_length: 3
              ),
            max_runs: 8
          ) do
      unique = System.unique_integer([:positive])

      fresh =
        fates
        |> Enum.with_index()
        |> Enum.map(fn {fate, index} -> seed_manual(fate, unique, index, admin) end)

      population = Process.get(:scope_population) ++ fresh
      Process.put(:scope_population, population)

      Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

      {:ok, result} = Retriever.retrieve("knowledgebase entry")

      allowed_ids =
        population
        |> Enum.filter(fn {fate, _manual} -> fate in [:keep, :revise] end)
        |> MapSet.new(fn {_fate, manual} -> manual.id end)

      revised_ids =
        population
        |> Enum.filter(fn {fate, _manual} -> fate == :revise end)
        |> MapSet.new(fn {_fate, manual} -> manual.id end)

      for excerpt <- result.excerpts do
        assert MapSet.member?(allowed_ids, excerpt.manual_id)
        refute excerpt.content =~ "stale-marker"

        if MapSet.member?(revised_ids, excerpt.manual_id) do
          assert excerpt.revision == 2
          assert excerpt.content =~ "current-marker"
        end
      end
    end
  end

  defp seed_manual(fate, unique, index, admin) do
    manual =
      Ash.create!(
        Manual,
        %{
          title: "Scope #{unique}-#{index}",
          slug: "scope-#{unique}-#{index}",
          body: seed_body(fate, unique, index)
        },
        action: :author,
        actor: admin
      )

    {fate, apply_fate(manual, fate, unique, index, admin)}
  end

  # Revised manuals start with a stale marker so a stale-revision leak
  # is detectable by content; every other fate carries a neutral body.
  defp seed_body(:revise, unique, index),
    do: "Knowledgebase entry stale-marker-#{unique}-#{index}."

  defp seed_body(_fate, unique, index),
    do: "Knowledgebase entry neutral-#{unique}-#{index}."

  defp apply_fate(manual, :keep, _unique, _index, _admin), do: manual

  defp apply_fate(manual, :archive, _unique, _index, admin) do
    Ash.update!(manual, %{}, action: :archive, actor: admin)
  end

  defp apply_fate(manual, :soft_delete, _unique, _index, admin) do
    Ash.update!(manual, %{}, action: :soft_delete, actor: admin)
  end

  defp apply_fate(manual, :revise, unique, index, admin) do
    Ash.update!(
      manual,
      %{body: "Knowledgebase entry current-marker-#{unique}-#{index}."},
      action: :revise,
      actor: admin
    )
  end
end
