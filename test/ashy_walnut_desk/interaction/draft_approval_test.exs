defmodule AshyWalnutDesk.Interaction.DraftApprovalTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, Channel, Compensation, Conversation, Draft, Inbox}

  test "approve sets metadata and registers action + compensation" do
    %{operator: operator, draft: draft} = seed_chain()

    assert {:ok, approved} =
             Ash.update(draft, %{compensation_body: "Offer remediation"},
               action: :approve,
               actor: operator
             )

    assert approved.status == :approved
    refute is_nil(approved.approved_at)
    assert approved.approved_by_id == operator.id

    [action] = Ash.read!(Action, authorize?: false)
    assert action.draft_id == approved.id
    assert action.status == :pending

    [compensation] = Ash.read!(Compensation, authorize?: false)
    assert compensation.action_id == action.id
    assert compensation.status == :registered
    assert compensation.body == "Offer remediation"
  end

  test "approve rejects blank compensation and non-drafting statuses" do
    %{operator: operator, draft: draft} = seed_chain()

    assert {:error, error} =
             Ash.update(draft, %{compensation_body: nil}, action: :approve, actor: operator)

    assert Exception.message(error) =~ "is required when approving a draft"

    {:ok, rejected} =
      Ash.update(draft, %{status: :rejected}, action: :edit_draft, actor: operator)

    assert {:error, non_drafting_error} =
             Ash.update(rejected, %{compensation_body: "X"}, action: :approve, actor: operator)

    assert Exception.message(non_drafting_error) =~ "draft_not_drafting"
  end

  defp seed_chain do
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
        %{inbox_id: inbox.id, body: "Draft body", status: :drafting},
        action: :compose_draft,
        actor: operator
      )

    %{operator: operator, draft: draft}
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
