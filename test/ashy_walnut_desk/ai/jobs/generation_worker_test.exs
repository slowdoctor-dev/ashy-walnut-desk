defmodule AshyWalnutDesk.AI.Jobs.GenerationWorkerTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.AI.Jobs.GenerationWorker
  alias AshyWalnutDesk.Interaction.{Draft, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.Persona

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    Application.put_env(:ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter) end)

    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    {:ok, _inbound} =
      Ash.create(
        Message,
        %{
          conversation_id: conversation.id,
          direction: :inbound,
          body: "Need help with scheduling."
        },
        action: :record_message,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Default Persona",
          slug: "default-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe prompt ", 8),
          disclosure_text: "AI-assisted draft.",
          guardrail_notes: "No unsupported claims.",
          model_override: "claude-sonnet-4-6"
        },
        action: :create,
        actor: admin
      )

    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: operator
      )

    %{draft: draft}
  end

  test "perform completes generation, persists metadata, and appends disclosure", %{draft: draft} do
    Phoenix.PubSub.subscribe(AshyWalnutDesk.PubSub, "draft:#{draft.id}")

    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 1,
               max_attempts: 3
             })

    assert_receive :generation_complete

    reloaded = Ash.get!(Draft, draft.id, authorize?: false)
    assert reloaded.status == :drafting
    assert reloaded.ai_model == "claude-sonnet-4-6"
    assert is_binary(reloaded.ai_prompt)
    assert is_binary(reloaded.ai_response)
    assert reloaded.ai_validator_output["passed?"] == true
    assert String.ends_with?(reloaded.body, "AI-assisted draft.")
  end
end
