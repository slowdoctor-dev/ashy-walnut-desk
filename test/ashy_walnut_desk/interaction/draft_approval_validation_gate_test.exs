defmodule AshyWalnutDesk.Interaction.DraftApprovalValidationGateTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Draft
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  setup do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    %{operator: operator, inbox: inbox}
  end

  test "approve rejects AI draft when validator did not pass", %{operator: operator, inbox: inbox} do
    draft =
      Fixtures.seed_draft(operator, inbox,
        body: "Generated body",
        ai_validator_output: %{"passed?" => false, "violations" => [%{code: :guarantee_claim}]}
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(draft, %{}, action: :approve, actor: operator)
  end

  test "approve allows AI draft when validator passed", %{operator: operator, inbox: inbox} do
    draft =
      Fixtures.seed_draft(operator, inbox,
        body: "Generated body",
        ai_validator_output: %{"passed?" => true, "violations" => []}
      )

    assert {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)
    assert approved.status == :approved
  end

  test "approve falls back to honest framing for manual drafts", %{
    operator: operator,
    inbox: inbox
  } do
    bad_manual =
      Fixtures.seed_draft(operator, inbox,
        body: "We can unsend this message",
        ai_validator_output: nil
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(bad_manual, %{}, action: :approve, actor: operator)

    good_manual =
      Fixtures.seed_draft(operator, inbox,
        body: "Please review this response before sending.",
        ai_validator_output: nil
      )

    assert {:ok, approved} = Ash.update(good_manual, %{}, action: :approve, actor: operator)
    assert approved.status == :approved
  end
end
