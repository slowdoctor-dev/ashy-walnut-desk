defmodule AshyWalnutDesk.Knowledge.ManualPolicyTest do
  @moduledoc """
  Story 5.1 AC2 — role matrix: admin writes, operator reads (including
  the body — manuals are operator reference material), viewer nothing.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Manual

  defp author!(admin) do
    Ash.create!(
      Manual,
      %{
        title: "Policy manual",
        slug: "policy-manual-#{System.unique_integer([:positive])}",
        body: "Operator-facing reference content."
      },
      action: :author,
      actor: admin
    )
  end

  test "admin and operator can read; viewer cannot" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    viewer = AccountsFixtures.create_user(:viewer)

    manual = author!(admin)

    assert {:ok, admin_rows} = Ash.read(Manual, action: :read, actor: admin)
    assert Enum.any?(admin_rows, &(&1.id == manual.id))

    assert {:ok, operator_rows} = Ash.read(Manual, action: :read, actor: operator)
    assert Enum.any?(operator_rows, &(&1.id == manual.id))

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Manual, action: :read, actor: viewer)
  end

  test "operator can read the body field (unlike Persona internals)" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)

    manual = author!(admin)

    assert {:ok, operator_row} = Ash.get(Manual, manual.id, actor: operator)
    assert operator_row.body == "Operator-facing reference content."
  end

  test "only admin can mutate" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    manual = author!(admin)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(
               Manual,
               %{title: "Nope", slug: "nope-#{System.unique_integer([:positive])}", body: "x"},
               action: :author,
               actor: operator
             )

    for action <- [:revise, :archive, :restore, :soft_delete] do
      params = if action == :revise, do: %{body: "nope"}, else: %{}

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(manual, params, action: action, actor: operator)
    end

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Manual, action: :read_with_archived, actor: operator)
  end
end
