defmodule AshyWalnutDesk.Interaction.ActionExecuteTest do
  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, Channel, Conversation, Draft, Inbox, Message}

  test "execute marks action executed, writes outbound message with approver, and marks inbox executed" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} = seed_approved_chain()

    {:ok, _} =
      Ash.update(draft, %{approved_at: DateTime.add(DateTime.utc_now(), -6, :second)},
        action: :edit_draft,
        actor: operator
      )

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

  defp seed_approved_chain do
    admin = create_user(:admin)
    operator = create_user(:operator)
    unique = System.unique_integer([:positive])

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "Identity #{unique}", primary_identifier: "+1555#{unique}"},
        action: :register_identity,
        actor: admin
      )

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "Thread", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{
          conversation_id: conversation.id,
          status: :drafting,
          summary: "Need response",
          recorded_by_id: operator.id
        },
        action: :record_inbox,
        actor: operator
      )

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "Draft body",
          compensation_body: "Compensate",
          status: :drafting
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)
    [action] = Ash.read!(Action, authorize?: false)

    %{operator: operator, draft: approved, action: action, inbox: inbox}
  end

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{System.unique_integer([:positive])}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end
end
