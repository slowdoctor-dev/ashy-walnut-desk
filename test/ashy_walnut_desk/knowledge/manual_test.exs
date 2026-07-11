defmodule AshyWalnutDesk.Knowledge.ManualTest do
  @moduledoc """
  Story 5.1 AC1 — Manual attributes, action set, revision bump, slug
  immutability, and soft-delete read filtering.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Manual

  defp author!(admin, attrs \\ %{}) do
    defaults = %{
      title: "Scheduling basics",
      slug: "scheduling-basics-#{System.unique_integer([:positive])}",
      body: "How we handle scheduling requests.\n\nAlways confirm the requested time."
    }

    Ash.create!(Manual, Map.merge(defaults, attrs), action: :author, actor: admin)
  end

  test "author enforces required fields, slug format, and slug uniqueness" do
    admin = AccountsFixtures.create_user(:admin)

    manual = author!(admin, %{slug: "front-desk-manual"})
    assert manual.revision == 1
    assert manual.status == :active
    assert is_nil(manual.deleted_at)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Manual,
               %{title: "Dup", slug: "front-desk-manual", body: "duplicate slug"},
               action: :author,
               actor: admin
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Manual,
               %{title: "Bad slug", slug: "Not A Slug!", body: "body"},
               action: :author,
               actor: admin
             )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Manual,
               %{title: "No body", slug: "no-body", body: ""},
               action: :author,
               actor: admin
             )
  end

  test "revise bumps revision, accepts title/body, and never accepts slug" do
    admin = AccountsFixtures.create_user(:admin)
    manual = author!(admin)

    {:ok, revised} =
      Ash.update(manual, %{body: "Updated operational guidance."},
        action: :revise,
        actor: admin
      )

    assert revised.revision == 2
    assert revised.body == "Updated operational guidance."

    {:ok, revised_again} =
      Ash.update(revised, %{title: "Scheduling basics v3"}, action: :revise, actor: admin)

    assert revised_again.revision == 3

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(revised_again, %{slug: "renamed"}, action: :revise, actor: admin)
  end

  test "archive flips status without deleting; restore returns to active" do
    admin = AccountsFixtures.create_user(:admin)
    manual = author!(admin)

    {:ok, archived} = Ash.update(manual, %{}, action: :archive, actor: admin)
    assert archived.status == :archived
    assert is_nil(archived.deleted_at)

    # Archived-but-not-deleted rows stay on the primary read.
    assert {:ok, _} = Ash.get(Manual, manual.id, actor: admin)

    {:ok, restored} = Ash.update(archived, %{}, action: :restore, actor: admin)
    assert restored.status == :active
  end

  test "soft_delete hides from primary read; read_with_archived still sees it" do
    admin = AccountsFixtures.create_user(:admin)
    manual = author!(admin)

    {:ok, deleted} = Ash.update(manual, %{}, action: :soft_delete, actor: admin)
    refute is_nil(deleted.deleted_at)
    assert deleted.status == :archived

    {:ok, visible} = Ash.read(Manual, actor: admin)
    refute Enum.any?(visible, &(&1.id == manual.id))

    all_rows = Ash.read!(Manual, action: :read_with_archived, actor: admin)
    assert Enum.any?(all_rows, &(&1.id == manual.id))

    {:ok, restored} = Ash.update(deleted, %{}, action: :restore, actor: admin)
    assert is_nil(restored.deleted_at)
    assert {:ok, _} = Ash.get(Manual, manual.id, actor: admin)
  end
end
