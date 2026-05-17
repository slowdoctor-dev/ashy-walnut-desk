defmodule AshyWalnutDesk.Interaction.CountdownGuardTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  # Note: no other AshyWalnutDesk.* aliases — `Fixtures` is the last
  # alias by alphabetical order within its sub-group.

  test "execute rejects under 5s and accepts at/over 5s" do
    admin = AccountsFixtures.create_user(:admin)

    for seconds <- [0, 1, 4] do
      %{operator: operator, draft: draft, action: action} =
        Fixtures.seed_approved_chain(admin: admin)

      Fixtures.backdate_approval!(draft, seconds)

      assert {:error, error} = Ash.update(action, %{}, action: :execute, actor: operator)
      assert Exception.message(error) =~ "countdown_violation"
    end

    for seconds <- [5, 10] do
      %{operator: operator, draft: draft, action: action} =
        Fixtures.seed_approved_chain(admin: admin)

      Fixtures.backdate_approval!(draft, seconds)

      assert {:ok, executed} = Ash.update(action, %{}, action: :execute, actor: operator)
      assert executed.status == :executed
    end
  end
end
