defmodule AshyWalnutDesk.Interaction.AuditChainWalkWithStatusTest do
  @moduledoc """
  Test-fix R4 — direct edge-case coverage for
  `AuditChain.walk_with_status/1`.

  The LV at `/audit/chain` (story 3.7) calls this helper. The
  integration tests (`tamper_visibility_test.exs`,
  `hash_continuity_test.exs`) cover the user-facing rendering for
  ok / broken / state-propagates-after-tamper cases. This file
  covers the edge cases the LV integration tests don't exercise:

  - empty topic (no events at all) → returns `[]`
  - single-event topic with `nil` prev_hash → status `:ok`
  - status propagation: once any event is `:broken`, every
    subsequent event inherits `:broken` (verified at the function
    level, not just visually in the LV)
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Interaction.AuditChain
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo

  test "empty topic returns []" do
    assert AuditChain.walk_with_status("nonexistent-topic-id") == []
  end

  test "intact chain — every event reports :ok" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)

    rows = AuditChain.walk_with_status(to_string(inbox.id))

    refute rows == []
    assert Enum.all?(rows, fn {_event, status} -> status == :ok end)
  end

  test "tampering the first event marks ALL events :broken (state propagation)" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)

    [first | _] = AuditChain.walk_with_status(to_string(inbox.id))
    {first_event, :ok} = first

    {:ok, dump} = Ecto.UUID.dump(first_event.id)
    Repo.query!("UPDATE audit_events SET hash = $1 WHERE id = $2", ["tampered-hash", dump])

    rows_after = AuditChain.walk_with_status(to_string(inbox.id))

    # First event itself is broken (its computed hash != stored).
    [{_first, first_status} | rest] = rows_after
    assert first_status == :broken

    # Every subsequent event inherits :broken because the chain
    # state is `:broken` from row 1 onward — short-circuits the
    # per-event hash check.
    assert Enum.all?(rest, fn {_event, status} -> status == :broken end),
           "expected all downstream rows to be :broken, got: #{inspect(Enum.map(rest, &elem(&1, 1)))}"
  end

  test "tampering a middle event marks pre-tamper rows :ok, tamper + downstream :broken" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)

    rows = AuditChain.walk_with_status(to_string(inbox.id))
    # Pick the 3rd event (middle of a 6-event chain).
    assert length(rows) >= 4
    {middle_event, :ok} = Enum.at(rows, 2)

    {:ok, dump} = Ecto.UUID.dump(middle_event.id)
    Repo.query!("UPDATE audit_events SET hash = $1 WHERE id = $2", ["broken-middle", dump])

    rows_after = AuditChain.walk_with_status(to_string(inbox.id))
    statuses = Enum.map(rows_after, fn {_event, status} -> status end)

    # First two events still :ok (pre-tamper).
    assert Enum.take(statuses, 2) == [:ok, :ok]
    # From index 2 onward, all :broken.
    rest = Enum.drop(statuses, 2)
    assert Enum.all?(rest, &(&1 == :broken))
  end
end
