defmodule AshyWalnutDesk.Interaction.ActionExecuteEnqueueTest do
  @moduledoc """
  Story 3.5 AC1 — `Action.:execute` schedules an Oban job
  (`Jobs.OutboundSend`) instead of inline-calling the adapter, and
  the 5-second `CountdownGuard` still gates the call. The job is not
  drained here; the worker behaviour is exercised by
  `jobs/outbound_send_test.exs`.

  Per ADR-023.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Interaction.Action
  alias AshyWalnutDesk.Interaction.Jobs.OutboundSend
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "execute flips Action :pending → :scheduled and enqueues OutboundSend job" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)

    assert action.status == :pending
    assert_empty_outbound_queue!()

    assert {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: operator)
    assert scheduled.status == :scheduled

    jobs = outbound_jobs_for(scheduled.id)
    assert length(jobs) == 1

    [job] = jobs
    assert job.worker == "AshyWalnutDesk.Interaction.Jobs.OutboundSend"
    assert job.queue == "outbound"
    assert job.args["action_id"] == scheduled.id
    assert job.args["kind"] == "action"
  end

  test "countdown still rejects execute under 5s (no job enqueued)" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 2)

    assert {:error, error} = Ash.update(action, %{}, action: :execute, actor: operator)
    assert Exception.message(error) =~ "countdown_violation"

    reloaded = Ash.get!(Action, action.id, authorize?: false)
    assert reloaded.status == :pending
    assert_empty_outbound_queue!()
  end

  test "Oban worker carries unique config keyed on (:action_id, :kind) per ADR-023" do
    config = OutboundSend.__opts__()
    unique = Keyword.fetch!(config, :unique)
    assert Keyword.fetch!(unique, :period) == 60
    assert Keyword.fetch!(unique, :keys) == [:action_id, :kind]
  end

  test "second :execute against a :scheduled Action fails the StatusTransition guard" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)

    assert {:ok, scheduled} = Ash.update(action, %{}, action: :execute, actor: operator)
    assert scheduled.status == :scheduled

    assert {:error, %Ash.Error.Invalid{} = err} =
             Ash.update(scheduled, %{}, action: :execute, actor: operator)

    assert Enum.any?(err.errors, fn
             %{message: msg} -> is_binary(msg) and msg =~ "invalid transition from :scheduled"
             _ -> false
           end)
  end

  defp outbound_jobs_for(action_id) do
    import Ecto.Query
    require Logger

    Oban.Job
    |> where([j], j.worker == "AshyWalnutDesk.Interaction.Jobs.OutboundSend")
    |> AshyWalnutDesk.Repo.all()
    |> Enum.filter(fn job -> job.args["action_id"] == action_id end)
  end

  defp assert_empty_outbound_queue! do
    assert outbound_jobs_count() == 0
  end

  defp outbound_jobs_count do
    import Ecto.Query

    Oban.Job
    |> where([j], j.worker == "AshyWalnutDesk.Interaction.Jobs.OutboundSend")
    |> AshyWalnutDesk.Repo.aggregate(:count, :id)
  end
end
