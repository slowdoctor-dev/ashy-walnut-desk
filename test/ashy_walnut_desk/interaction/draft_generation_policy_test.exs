defmodule AshyWalnutDesk.Interaction.DraftGenerationPolicyTest do
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

    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, body: ""}, action: :generate, actor: operator)

    %{draft: draft, operator: operator}
  end

  test "complete_generation is denied without worker context", %{draft: draft, operator: operator} do
    assert {:error, %Ash.Error.Forbidden{}} =
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
               actor: operator
             )
  end

  test "fail_generation is denied on context mismatch", %{draft: draft} do
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(
               draft,
               %{ai_validator_output: %{"error_class" => "provider_error"}},
               action: :fail_generation,
               context: %{from_generation_worker: false}
             )
  end

  test "worker context allows completion and failure transitions", %{
    draft: draft,
    operator: operator
  } do
    assert {:ok, completed} =
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

    assert {:ok, generating} =
             Ash.create(Draft, %{inbox_id: completed.inbox_id, body: ""},
               action: :generate,
               actor: operator
             )

    assert {:ok, failed} =
             Ash.update(
               generating,
               %{ai_validator_output: %{"error_class" => "provider_error"}},
               action: :fail_generation,
               context: %{from_generation_worker: true}
             )

    assert failed.status == :rejected
  end
end
