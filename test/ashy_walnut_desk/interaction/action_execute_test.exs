defmodule AshyWalnutDesk.Interaction.ActionExecuteTest do
  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{Inbox, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "execute marks action executed, writes outbound message with approver, and marks inbox executed" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    Fixtures.backdate_approval!(draft, 6)

    assert {:ok, executed} = Ash.update(action, %{}, action: :execute, actor: operator)
    assert executed.status == :executed
    refute is_nil(executed.executed_at)

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read_one!()

    assert outbound.approved_by_id == draft.approved_by_id
    refute is_nil(outbound.sent_at)

    {:ok, reloaded_inbox} = Ash.get(Inbox, inbox.id, actor: operator)
    assert reloaded_inbox.status == :executed
  end
end
