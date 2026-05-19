defmodule AshyWalnutDesk.Interaction.SensitiveFieldVisibilityTest do
  use AshyWalnutDesk.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Action, Compensation, Conversation, Draft, Inbox, Message}
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

  # Sec-fix R7: Action.adapter_response holds Twilio's response,
  # which echoes the recipient phone number under `"to"`. Action.error
  # holds the provider error string. Both are viewer-forbidden.
  test "viewer cannot read Action.adapter_response or Action.error" do
    chain = InteractionFixtures.seed_approved_chain()
    viewer = AccountsFixtures.create_user(:viewer)

    InteractionFixtures.backdate_approval!(chain.draft, 6)
    executed = InteractionFixtures.execute_action!(chain.action, chain.operator)
    # Sanity: the action was driven to :executed and has an adapter_response.
    assert executed.status == :executed
    assert is_map(executed.adapter_response)

    {:ok, viewer_action} = Ash.get(Action, executed.id, actor: viewer)
    assert match?(%Ash.ForbiddenField{}, viewer_action.adapter_response)
    assert match?(%Ash.ForbiddenField{}, viewer_action.error)
    # Status remains visible — not sensitive.
    assert viewer_action.status == :executed
  end

  test "operator retains access to Action.adapter_response and Action.error" do
    chain = InteractionFixtures.seed_approved_chain()

    InteractionFixtures.backdate_approval!(chain.draft, 6)
    executed = InteractionFixtures.execute_action!(chain.action, chain.operator)

    {:ok, operator_action} = Ash.get(Action, executed.id, actor: chain.operator)
    assert is_map(operator_action.adapter_response)
    # `.error` may be nil on a successful send — both nil and a
    # string are acceptable "operator can read this" outcomes.
    refute match?(%Ash.ForbiddenField{}, operator_action.error)
  end

  test "viewer cannot read Compensation.adapter_response or Compensation.error" do
    chain = InteractionFixtures.seed_approved_chain()
    viewer = AccountsFixtures.create_user(:viewer)

    InteractionFixtures.backdate_approval!(chain.draft, 6)
    executed = InteractionFixtures.execute_action!(chain.action, chain.operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!(authorize?: false)

    {:ok, viewer_compensation} = Ash.get(Compensation, compensation.id, actor: viewer)
    assert match?(%Ash.ForbiddenField{}, viewer_compensation.adapter_response)
    assert match?(%Ash.ForbiddenField{}, viewer_compensation.error)
  end

  # Sec-fix R8 + R12: Draft text fields and AI artifacts carry
  # operator-drafted text and matching compensation message.
  # Viewer was previously able to read both via the resource-level
  # `:read` policy. Field policies now mask them.
  test "viewer cannot read Draft.body / compensation_body / ai_prompt / ai_response" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    viewer = AccountsFixtures.create_user(:viewer)

    identity = InteractionFixtures.seed_identity(admin)
    channel = InteractionFixtures.seed_channel(admin)
    conversation = InteractionFixtures.seed_conversation(operator, identity, channel)
    inbox = InteractionFixtures.seed_inbox(operator, conversation)

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "draft body",
          compensation_body: "draft compensation",
          status: :drafting,
          ai_prompt: "draft prompt with pii",
          ai_response: "model output with pii"
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, viewer_draft} = Ash.get(Draft, draft.id, actor: viewer)
    assert match?(%Ash.ForbiddenField{}, viewer_draft.body)
    assert match?(%Ash.ForbiddenField{}, viewer_draft.compensation_body)
    assert match?(%Ash.ForbiddenField{}, viewer_draft.ai_prompt)
    assert match?(%Ash.ForbiddenField{}, viewer_draft.ai_response)
    # Status / FKs remain readable so the chain view can still show
    # "Draft #N — approved" without leaking the message text.
    assert viewer_draft.status in [:drafting, :approved]
    refute is_nil(viewer_draft.inbox_id)
  end

  test "operator retains access to Draft.body / compensation_body / ai_prompt / ai_response" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = InteractionFixtures.seed_identity(admin)
    channel = InteractionFixtures.seed_channel(admin)
    conversation = InteractionFixtures.seed_conversation(operator, identity, channel)
    inbox = InteractionFixtures.seed_inbox(operator, conversation)

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "draft body",
          compensation_body: "draft compensation",
          status: :drafting,
          ai_prompt: "draft prompt with pii",
          ai_response: "model output with pii"
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, operator_draft} = Ash.get(Draft, draft.id, actor: operator)
    assert is_binary(operator_draft.body)
    assert is_binary(operator_draft.compensation_body)
    assert is_binary(operator_draft.ai_prompt)
    assert is_binary(operator_draft.ai_response)
  end
end
