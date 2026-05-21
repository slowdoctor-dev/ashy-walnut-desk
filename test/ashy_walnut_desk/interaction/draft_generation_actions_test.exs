defmodule AshyWalnutDesk.Interaction.DraftGenerationActionsTest do
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

  test "generate creates a generating draft with empty body", %{operator: operator, inbox: inbox} do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id}, action: :generate, actor: operator)

    assert draft.status == :generating
    assert draft.body == ""
  end

  test "complete_generation transitions generating -> drafting with worker context", %{
    operator: operator,
    inbox: inbox
  } do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id}, action: :generate, actor: operator)

    {:ok, completed} =
      Ash.update(
        draft,
        %{
          body: "Generated draft body",
          ai_prompt: "prompt",
          ai_model: "claude-sonnet-4-6",
          ai_response: "Generated draft body",
          ai_validator_output: %{"passed?" => true, "violations" => []}
        },
        action: :complete_generation,
        context: %{from_generation_worker: true}
      )

    assert completed.status == :drafting
  end

  test "fail_generation transitions generating -> rejected with worker context", %{
    operator: operator,
    inbox: inbox
  } do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id}, action: :generate, actor: operator)

    {:ok, failed} =
      Ash.update(
        draft,
        %{ai_validator_output: %{"error_class" => "provider_error"}},
        action: :fail_generation,
        context: %{from_generation_worker: true}
      )

    assert failed.status == :rejected
  end
end
