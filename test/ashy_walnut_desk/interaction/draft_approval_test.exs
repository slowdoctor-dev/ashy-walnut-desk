defmodule AshyWalnutDesk.Interaction.DraftApprovalTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Action, Compensation}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "approve sets metadata and registers action + compensation" do
    %{operator: operator, draft: draft} = drafting_chain()

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
    %{operator: operator, draft: draft} = drafting_chain()

    assert {:error, error} =
             Ash.update(draft, %{compensation_body: nil}, action: :approve, actor: operator)

    assert Exception.message(error) =~ "is required when approving a draft"

    {:ok, rejected} =
      Ash.update(draft, %{status: :rejected}, action: :revise, actor: operator)

    assert {:error, non_drafting_error} =
             Ash.update(rejected, %{compensation_body: "X"}, action: :approve, actor: operator)

    assert Exception.message(non_drafting_error) =~ "draft_not_drafting"
  end

  # The shared `Fixtures.seed_approved_chain/1` returns an
  # already-approved draft; this test exercises `:approve` directly,
  # so we want a draft still at `:drafting`. Build the chain pieces
  # but stop before approval.
  defp drafting_chain do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)
    draft = Fixtures.seed_draft(operator, inbox, body: "Draft body", compensation_body: nil)

    %{operator: operator, draft: draft}
  end
end
