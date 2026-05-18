defmodule AshyWalnutDesk.Interaction.ActionExecuteChainIntegrationTest do
  @moduledoc """
  Story 3.5 AC4 — successful job completion updates the full Phase 2
  chain (Action → outbound Message → Inbox) and the audit chain
  remains hash-continuous after the new `:action_scheduled` event
  joins the sequence.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Interaction.{AuditChain, Inbox, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "chain ends in 6 hash-linked events; audit walk reports ok" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)

    executed = Fixtures.execute_action!(action, operator)
    assert executed.status == :executed

    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    assert length(events) == 6

    event_types = Enum.map(events, & &1.event_type)

    assert event_types == [
             :inbox_opened,
             :draft_started,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed
           ]

    # Hash-continuity: each prev_hash equals the previous row's hash.
    [first | rest] = events
    assert is_nil(first.prev_hash)

    Enum.reduce(rest, first.hash, fn event, prev_hash ->
      assert event.prev_hash == prev_hash
      event.hash
    end)

    # :action_executed payload now reports outcome :ok per ADR-023.
    [scheduled, executed_evt] = Enum.drop(events, 4)
    assert scheduled.event_type == :action_scheduled
    refute Map.has_key?(scheduled.payload, "outcome")

    assert executed_evt.event_type == :action_executed
    assert executed_evt.payload["outcome"] == "ok"
  end

  test "Action.adapter_response is persisted on the row" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)

    executed = Fixtures.execute_action!(action, operator)

    assert is_map(executed.adapter_response)
  end

  require Ash.Query

  test "outbound Message persists Action.outbound_idempotency_key for audit correlation" do
    %{operator: operator, draft: draft, action: action} = Fixtures.seed_approved_chain()
    Fixtures.backdate_approval!(draft, 6)

    _executed = Fixtures.execute_action!(action, operator)

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(direction == :outbound)
      |> Ash.read_one!()

    assert outbound.outbound_idempotency_key == action.outbound_idempotency_key

    {:ok, inbox} =
      Ash.get(Inbox, draft.inbox_id, actor: operator)

    assert inbox.status == :executed
  end
end
