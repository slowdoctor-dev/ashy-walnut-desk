defmodule AshyWalnutDesk.Interaction.CompensationTriggerTest do
  @moduledoc """
  Story 3.6 AC1 — operator/admin can drive a Compensation through
  the two-step trigger flow (`:initiate_trigger` → countdown →
  `:trigger`) and the worker finalizes status to `:triggered`.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{Compensation, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp executed_chain do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    %{operator: operator, action: executed, compensation: compensation}
  end

  defp backdate_trigger_initiated!(compensation, seconds \\ 6) do
    new_ts = DateTime.add(DateTime.utc_now(), -seconds, :second)

    compensation
    |> Ecto.Changeset.change(%{trigger_initiated_at: new_ts})
    |> AshyWalnutDesk.Repo.update!()
    |> then(&Ash.get!(Compensation, &1.id, authorize?: false))
  end

  defp trigger_and_drain!(compensation, operator) do
    backdated = backdate_trigger_initiated!(compensation)
    {:ok, scheduled} = Ash.update(backdated, %{}, action: :trigger, actor: operator)
    Oban.drain_queue(queue: :outbound, with_recursion: true)
    Ash.get!(Compensation, scheduled.id, authorize?: false)
  end

  test "operator drives Compensation :registered → :triggering → :scheduled → :triggered" do
    %{operator: operator, compensation: compensation} = executed_chain()
    assert compensation.status == :registered

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)
    assert triggering.status == :triggering
    refute is_nil(triggering.trigger_initiated_at)
    assert is_binary(triggering.outbound_idempotency_key)
    assert String.starts_with?(triggering.outbound_idempotency_key, "compensation-")

    final = trigger_and_drain!(triggering, operator)
    assert final.status == :triggered
    refute is_nil(final.triggered_at)
  end

  test "compensation send creates a second outbound Message (operator approver propagated)" do
    %{operator: operator, action: action, compensation: compensation} = executed_chain()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)
    _final = trigger_and_drain!(triggering, operator)

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.Query.sort(created_at: :asc)
      |> Ash.read!()

    assert length(outbound) == 2
    [primary, comp_message] = outbound

    refute is_nil(primary.approved_by_id)
    assert comp_message.approved_by_id == primary.approved_by_id
    assert comp_message.outbound_idempotency_key
    refute comp_message.outbound_idempotency_key == primary.outbound_idempotency_key

    # The compensation message body persists from the compensation
    # row, not the original draft body.
    assert comp_message.body == compensation.body

    # Action stays :executed; compensation now :triggered.
    reloaded_action = Ash.get!(AshyWalnutDesk.Interaction.Action, action.id, authorize?: false)
    assert reloaded_action.status == :executed
  end

  test ":trigger requires :triggering status (no skipping initiate_trigger)" do
    %{operator: operator, compensation: compensation} = executed_chain()

    assert {:error, %Ash.Error.Invalid{} = err} =
             Ash.update(compensation, %{}, action: :trigger, actor: operator)

    assert Enum.any?(err.errors, fn
             %{message: msg} -> is_binary(msg) and msg =~ "invalid transition from :registered"
             _ -> false
           end)
  end

  test "viewer role cannot initiate trigger" do
    %{compensation: compensation} = executed_chain()
    viewer = AshyWalnutDesk.AccountsFixtures.create_user(:viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(compensation, %{}, action: :initiate_trigger, actor: viewer)
  end
end
