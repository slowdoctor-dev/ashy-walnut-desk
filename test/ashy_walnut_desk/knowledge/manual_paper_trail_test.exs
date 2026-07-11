defmodule AshyWalnutDesk.Knowledge.ManualPaperTrailTest do
  @moduledoc """
  Story 5.1 AC3 — paper-trail versions for author/revise/archive with
  the sensitive `body` redacted, and version rows admin-only.
  """

  use AshyWalnutDesk.DataCase, async: false

  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Manual

  test "author/revise/archive record redacted version rows" do
    admin = AccountsFixtures.create_user(:admin)

    {:ok, manual} =
      Ash.create(
        Manual,
        %{
          title: "Trail manual",
          slug: "trail-manual",
          body: "Original operational guidance."
        },
        action: :author,
        actor: admin
      )

    {:ok, revised} =
      Ash.update(manual, %{body: "Revised operational guidance."},
        action: :revise,
        actor: admin
      )

    assert revised.revision == 2

    {:ok, _archived} = Ash.update(revised, %{}, action: :archive, actor: admin)

    versions =
      Manual.Version
      |> Ash.Query.filter(version_source_id == ^manual.id)
      |> Ash.read!(action: :read, authorize?: false)

    assert length(versions) >= 3

    assert Enum.any?(versions, fn version ->
             Map.get(version.changes || %{}, "body") == "REDACTED"
           end)

    assert Enum.all?(versions, fn version ->
             Map.get(version.changes || %{}, "body") in [nil, "REDACTED"]
           end)
  end

  test "version rows are admin-only" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)

    {:ok, _manual} =
      Ash.create(
        Manual,
        %{title: "Versions", slug: "versions-manual", body: "Guarded content."},
        action: :author,
        actor: admin
      )

    assert {:ok, _rows} = Ash.read(Manual.Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Manual.Version, actor: operator)
  end
end
