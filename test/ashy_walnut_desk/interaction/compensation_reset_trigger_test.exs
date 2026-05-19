defmodule AshyWalnutDesk.Interaction.CompensationResetTriggerTest do
  @moduledoc """
  Story 3.fix — admin can reset a Compensation stuck in `:triggering`
  back to `:registered`. This covers the case where an operator
  clicks "Trigger compensation" (which flips status `:registered →
  :triggering` and stamps `trigger_initiated_at`) and then the LV
  crashes / browser tab closes before the 5-second countdown
  elapses. Without recovery the compensation is permanently stuck.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Compensation
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp setup_triggering_compensation(admin) do
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

    %{admin: admin, operator: operator, compensation: triggering}
  end

  test "admin can :reset_trigger to clear stuck :triggering state" do
    admin = AccountsFixtures.create_user(:admin)
    %{compensation: comp} = setup_triggering_compensation(admin)

    assert comp.status == :triggering
    refute is_nil(comp.trigger_initiated_at)
    assert is_binary(comp.outbound_idempotency_key)

    assert {:ok, reset} = Ash.update(comp, %{}, action: :reset_trigger, actor: admin)
    assert reset.status == :registered
    assert is_nil(reset.trigger_initiated_at)
    assert is_nil(reset.outbound_idempotency_key)
  end

  test "operator cannot :reset_trigger (admin-only)" do
    admin = AccountsFixtures.create_user(:admin)
    %{operator: operator, compensation: comp} = setup_triggering_compensation(admin)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(comp, %{}, action: :reset_trigger, actor: operator)
  end

  test ":reset_trigger only valid from :triggering" do
    admin = AccountsFixtures.create_user(:admin)

    %{operator: operator, draft: draft, action: action} =
      Fixtures.seed_approved_chain(admin: admin)

    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    # :registered is the wrong from-state.
    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(compensation, %{}, action: :reset_trigger, actor: admin)
  end

  test "after :reset_trigger the operator can :initiate_trigger again with fresh state" do
    admin = AccountsFixtures.create_user(:admin)
    %{operator: operator, compensation: comp} = setup_triggering_compensation(admin)

    original_key = comp.outbound_idempotency_key

    {:ok, reset} = Ash.update(comp, %{}, action: :reset_trigger, actor: admin)
    {:ok, retriggered} = Ash.update(reset, %{}, action: :initiate_trigger, actor: operator)

    assert retriggered.status == :triggering
    # Fresh idempotency key on retry — prior :triggering attempt was
    # cleared, so a future Twilio send won't share an idempotency key
    # with whatever the original attempt might have queued.
    refute retriggered.outbound_idempotency_key == original_key
  end
end
