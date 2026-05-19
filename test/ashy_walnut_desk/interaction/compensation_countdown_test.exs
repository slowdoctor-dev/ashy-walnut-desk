defmodule AshyWalnutDesk.Interaction.CompensationCountdownTest do
  @moduledoc """
  Story 3.6 AC2 — `Compensation.:trigger` requires the 5-second
  countdown window since `:initiate_trigger` stamped
  `trigger_initiated_at`. Parity with `Action.:execute` per ADR-013.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.Compensation
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo

  setup do
    %{admin: AshyWalnutDesk.AccountsFixtures.create_user(:admin)}
  end

  defp setup_compensation(admin) do
    %{operator: operator, draft: draft, action: action} =
      Fixtures.seed_approved_chain(admin: admin)

    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)

    %{operator: operator, compensation: triggering}
  end

  defp backdate!(compensation, seconds) do
    new_ts = DateTime.add(DateTime.utc_now(), -seconds, :second)

    compensation
    |> Ecto.Changeset.change(%{trigger_initiated_at: new_ts})
    |> Repo.update!()
    |> then(&Ash.get!(Compensation, &1.id, authorize?: false))
  end

  test ":trigger rejects when fewer than 5 seconds have elapsed since initiate_trigger", %{
    admin: admin
  } do
    # NOTE: don't use seconds=4 here — slow CI can take 1s+ between
    # `backdate!` writing the row and `Ash.update(:trigger)` reading
    # it, pushing the effective elapsed time past 5s and flaking the
    # rejection assertion. Stay 2+ seconds under the 5s threshold.
    for seconds <- [0, 1, 2] do
      %{operator: operator, compensation: comp} = setup_compensation(admin)
      comp = backdate!(comp, seconds)

      assert {:error, err} = Ash.update(comp, %{}, action: :trigger, actor: operator)
      assert Exception.message(err) =~ "countdown_violation"

      reloaded = Ash.get!(Compensation, comp.id, authorize?: false)
      assert reloaded.status == :triggering
    end
  end

  test ":trigger accepts at/after 5 seconds", %{admin: admin} do
    for seconds <- [5, 10, 60] do
      %{operator: operator, compensation: comp} = setup_compensation(admin)
      comp = backdate!(comp, seconds)

      assert {:ok, scheduled} = Ash.update(comp, %{}, action: :trigger, actor: operator)
      assert scheduled.status == :scheduled
    end
  end
end
