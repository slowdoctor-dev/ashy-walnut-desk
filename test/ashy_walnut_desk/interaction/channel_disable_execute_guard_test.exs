defmodule AshyWalnutDesk.Interaction.ChannelDisableExecuteGuardTest do
  @moduledoc """
  Story 3.5 AC5 — operator/admin can `Channel.:disable` between
  approval and execute; the Oban worker re-checks `channel.enabled?`
  at job time so a race (channel disabled after the job is enqueued
  but before it runs) still fails-safe with no outbound HTTP and no
  Twilio request. Mirrors the Phase 2 F4 guard but now enforced in
  the worker, not in the LV.
  """

  use AshyWalnutDesk.DataCase, async: false
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{Action, Channel, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "channel disabled before drain: worker terminal-fails Action; no outbound Message" do
    %{admin: admin, operator: operator, draft: draft, action: action, channel: channel} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)

    # Operator clicks send (countdown elapsed).
    assert {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: operator)
    assert scheduled.status == :scheduled

    # Admin disables the channel AFTER the job is enqueued — simulates
    # an operator pulling the kill-switch while the worker hasn't
    # picked the job up yet.
    {:ok, _} = Ash.update(channel, %{}, action: :disable, actor: admin)

    # Drain — worker should re-fetch and refuse.
    Oban.drain_queue(queue: :outbound, with_recursion: true)

    reloaded = Ash.get!(Action, action.id, authorize?: false)
    assert reloaded.status == :failed
    assert reloaded.error =~ "disabled"

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(direction == :outbound)
      |> Ash.read!()

    assert outbound == []
  end

  test "channel disabled while still pending (operator path): Action.:execute returns ok but worker terminal-fails" do
    # Channel disabled even before the operator clicked send. The
    # `Action.:execute` policy doesn't gate on channel.enabled?
    # (intentionally — keeps the LV path simple). The worker is the
    # gate.
    %{admin: admin, operator: operator, draft: draft, action: action, channel: channel} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    {:ok, _} = Ash.update(channel, %{}, action: :disable, actor: admin)

    executed = Fixtures.execute_action!(action, operator)
    assert executed.status == :failed
    assert executed.error =~ "disabled"
  end

  test "the F4 disable guard is re-checked at job time (not bypassable via :execute timing)" do
    # Regression of the Phase 2 F4 (security review) hardening: a
    # disabled `Channel` must never produce an outbound `Message`,
    # even when `Action.:execute` is allowed to flip status. The
    # worker is the enforcement point.
    %{admin: admin, operator: operator, draft: draft, action: action, channel: channel} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    {:ok, _} = Ash.update(channel, %{}, action: :disable, actor: admin)

    executed = Fixtures.execute_action!(action, operator)
    assert executed.status == :failed

    refute Channel
           |> Ash.Query.for_read(:read, %{}, authorize?: false)
           |> Ash.Query.filter(id == ^channel.id)
           |> Ash.read_one!()
           |> Map.fetch!(:enabled?)
  end
end
