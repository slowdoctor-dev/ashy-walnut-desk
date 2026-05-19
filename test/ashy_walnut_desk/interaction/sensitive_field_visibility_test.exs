defmodule AshyWalnutDesk.Interaction.SensitiveFieldVisibilityTest do
  use AshyWalnutDesk.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Compensation, Conversation, Inbox, Message}
  alias AshyWalnutDesk.InteractionFixtures

  test "viewer cannot read Message.body / Compensation.body / Inbox.summary / Conversation.subject" do
    chain = InteractionFixtures.seed_approved_chain()
    viewer = AccountsFixtures.create_user(:viewer)

    InteractionFixtures.backdate_approval!(chain.draft, 6)
    _executed = InteractionFixtures.execute_action!(chain.action, chain.operator)

    message =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read_one!(authorize?: false)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^chain.action.id))
      |> Ash.read_one!(authorize?: false)

    {:ok, inbox} = Ash.get(Inbox, chain.inbox.id, actor: viewer)
    {:ok, conversation} = Ash.get(Conversation, chain.conversation.id, actor: viewer)
    {:ok, viewer_message} = Ash.get(Message, message.id, actor: viewer)
    {:ok, viewer_compensation} = Ash.get(Compensation, compensation.id, actor: viewer)

    assert match?(%Ash.ForbiddenField{}, inbox.summary)
    assert match?(%Ash.ForbiddenField{}, conversation.subject)
    assert match?(%Ash.ForbiddenField{}, viewer_message.body)
    assert match?(%Ash.ForbiddenField{}, viewer_compensation.body)
  end

  test "operator retains access to the same sensitive fields" do
    chain = InteractionFixtures.seed_approved_chain()

    InteractionFixtures.backdate_approval!(chain.draft, 6)
    _executed = InteractionFixtures.execute_action!(chain.action, chain.operator)

    message =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read_one!(authorize?: false)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^chain.action.id))
      |> Ash.read_one!(authorize?: false)

    {:ok, inbox} = Ash.get(Inbox, chain.inbox.id, actor: chain.operator)
    {:ok, conversation} = Ash.get(Conversation, chain.conversation.id, actor: chain.operator)
    {:ok, operator_message} = Ash.get(Message, message.id, actor: chain.operator)
    {:ok, operator_compensation} = Ash.get(Compensation, compensation.id, actor: chain.operator)

    assert is_binary(inbox.summary)
    assert is_binary(conversation.subject)
    assert is_binary(operator_message.body)
    assert is_binary(operator_compensation.body)
  end
end
