defmodule AshyWalnutDesk.Interaction.InboundActorPolicyTest do
  @moduledoc """
  Story 3.3 AC5 — the inbound-webhook system actor cannot drive
  send-path actions. ADR-024's lockdown test. The system actor's
  only legitimate uses are `FromInboundWebhook`-gated actions
  (Inbox.:record_inbound, Identity.:register_provisional,
  Message.:record_message :inbound).
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.SystemActor
  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.InteractionFixtures

  alias AshyWalnutDesk.Interaction.{
    Action,
    Conversation,
    Inbox,
    Message
  }

  test "system actor is the ADR-024 inbound-only singleton" do
    actor = SystemActor.ensure!()
    assert actor.role == :system
    assert to_string(actor.email) == SystemActor.email()
  end

  test "system actor cannot drive Draft.:approve (send-path action)" do
    system_actor = SystemActor.ensure!()
    %{draft: draft} = drafting_chain()

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(draft, %{compensation_body: "X"},
               action: :approve,
               actor: system_actor
             )
  end

  test "system actor cannot drive Action.:execute (send-path action)" do
    system_actor = SystemActor.ensure!()
    %{operator: operator, draft: draft} = drafting_chain()

    {:ok, approved} =
      Ash.update(draft, %{compensation_body: "Comp"},
        action: :approve,
        actor: operator
      )

    approved_id = approved.id

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved_id))
      |> Ash.read_one!(authorize?: false)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(action, %{}, action: :execute, actor: system_actor)
  end

  test "system actor cannot drive Inbox.:record_inbox (operator-only path)" do
    system_actor = SystemActor.ensure!()
    %{conversation: conversation} = conversation_only()

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(
               Inbox,
               %{conversation_id: conversation.id, summary: "should not work"},
               action: :record_inbox,
               actor: system_actor
             )
  end

  test "system actor cannot drive Message.:record_message with :outbound direction" do
    system_actor = SystemActor.ensure!()
    %{conversation: conversation} = conversation_only()

    # Outbound rejected by the validation (requires from_action_execute
    # context) before the policy gate fires. Either error class is
    # "system actor can't do this"; both are acceptable rejections.
    assert {:error, error} =
             Ash.create(
               Message,
               %{
                 conversation_id: conversation.id,
                 direction: :outbound,
                 body: "should not work"
               },
               action: :record_message,
               actor: system_actor
             )

    assert error.__struct__ in [Ash.Error.Forbidden, Ash.Error.Invalid]
  end

  defp conversation_only do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = InteractionFixtures.seed_identity(admin)
    channel = InteractionFixtures.seed_channel(admin)
    conversation = InteractionFixtures.seed_conversation(operator, identity, channel)
    %{admin: admin, operator: operator, channel: channel, conversation: conversation}
  end

  defp drafting_chain do
    ctx = conversation_only()
    inbox = InteractionFixtures.seed_inbox(ctx.operator, ctx.conversation, summary: "S")
    draft = InteractionFixtures.seed_draft(ctx.operator, inbox)
    Map.merge(ctx, %{inbox: inbox, draft: draft})
  end
end
