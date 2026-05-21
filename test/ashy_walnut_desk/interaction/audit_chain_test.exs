defmodule AshyWalnutDesk.Interaction.AuditChainTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Interaction.AuditChain
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "chain writes six linked events for inbox -> draft -> approve -> schedule -> execute" do
    %{operator: operator, inbox: inbox, draft: draft, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)

    _executed = Fixtures.execute_action!(action, operator)

    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    assert length(events) == 6

    assert Enum.map(events, & &1.event_type) == [
             :inbox_opened,
             :draft_started,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed
           ]

    [first | rest] = events
    assert is_nil(first.prev_hash)

    Enum.reduce(rest, first.hash, fn event, prev_hash ->
      assert event.prev_hash == prev_hash
      event.hash
    end)
  end

  test "canonicalize_payload rejects unknown keys for each event type" do
    for event_type <- [
          :inbox_opened,
          :draft_started,
          :draft_generation_requested,
          :draft_generation_completed,
          :draft_generation_failed,
          :draft_superseded,
          :draft_approved,
          :action_scheduled,
          :action_executed,
          :compensation_registered
        ] do
      assert {:error, {:invalid_payload_key, :rogue}} =
               AuditChain.canonicalize_payload(event_type, %{rogue: "x"})
    end
  end
end
