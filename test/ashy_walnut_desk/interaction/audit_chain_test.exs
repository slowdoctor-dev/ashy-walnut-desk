defmodule AshyWalnutDesk.Interaction.AuditChainTest do
  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, AuditChain, Channel, Conversation, Draft, Inbox}

  test "chain writes five linked events for inbox -> draft -> approve -> execute" do
    %{operator: operator, inbox: inbox, draft: draft, action: action} = seed_approved_chain()

    {:ok, _draft} =
      Ash.update(draft, %{approved_at: DateTime.add(DateTime.utc_now(), -6, :second)},
        action: :edit_draft,
        actor: operator
      )

    assert {:ok, _executed} = Ash.update(action, %{}, action: :execute, actor: operator)

    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    assert length(events) == 5

    assert Enum.map(events, & &1.event_type) == [
             :inbox_opened,
             :draft_started,
             :draft_approved,
             :compensation_registered,
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
          :draft_approved,
          :action_executed,
          :compensation_registered
        ] do
      assert {:error, {:invalid_payload_key, :rogue}} =
               AuditChain.canonicalize_payload(event_type, %{rogue: "x"})
    end
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

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!(authorize?: false)

    %{operator: operator, inbox: inbox, draft: approved, action: action}
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
