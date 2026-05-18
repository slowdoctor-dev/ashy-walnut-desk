defmodule AshyWalnutDesk.Interaction.CompensationAuditChainTest do
  @moduledoc """
  Story 3.6 AC5 — compensation invocation writes `:compensation_scheduled`
  + `:compensation_executed` audit events and the resulting chain
  passes `mix audit.verify`.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{AuditChain, Compensation}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo

  defp drive_full_chain do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)
    new_ts = DateTime.add(DateTime.utc_now(), -6, :second)

    triggering =
      triggering
      |> Ecto.Changeset.change(%{trigger_initiated_at: new_ts})
      |> Repo.update!()
      |> then(&Ash.get!(Compensation, &1.id, authorize?: false))

    {:ok, _scheduled} = Ash.update(triggering, %{}, action: :trigger, actor: operator)
    Oban.drain_queue(queue: :outbound, with_recursion: true)

    %{inbox: inbox, compensation: Ash.get!(Compensation, compensation.id, authorize?: false)}
  end

  test "chain has 8 hash-linked events with compensation events at the tail" do
    %{inbox: inbox, compensation: compensation} = drive_full_chain()
    assert compensation.status == :triggered

    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    assert length(events) == 8

    assert Enum.map(events, & &1.event_type) == [
             :inbox_opened,
             :draft_started,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed,
             :compensation_scheduled,
             :compensation_executed
           ]

    [first | rest] = events
    assert is_nil(first.prev_hash)

    Enum.reduce(rest, first.hash, fn event, prev_hash ->
      assert event.prev_hash == prev_hash
      event.hash
    end)

    # compensation_executed carries outcome :ok on success.
    {scheduled, executed} = events |> Enum.take(-2) |> List.to_tuple()
    assert scheduled.event_type == :compensation_scheduled
    refute Map.has_key?(scheduled.payload, "outcome")

    assert executed.event_type == :compensation_executed
    assert executed.payload["outcome"] == "ok"
  end

  test "audit.verify is green after compensation send" do
    %{inbox: inbox} = drive_full_chain()

    {:ok, events} = AuditChain.walk(to_string(inbox.id))
    refute Enum.empty?(events)

    # Recompute chain locally to mirror what `mix audit.verify` does.
    Enum.reduce(events, "", fn event, prev_hash ->
      payload = event.payload || %{}
      assert {:ok, canonical} = AuditChain.canonicalize_payload(event.event_type, payload)
      json = Jason.encode!(canonical)
      prev = if prev_hash == "", do: nil, else: prev_hash
      computed = AuditChain.compute_hash(prev, json)
      assert computed == event.hash, "hash mismatch at #{inspect(event.event_type)}"
      event.hash
    end)
  end
end
