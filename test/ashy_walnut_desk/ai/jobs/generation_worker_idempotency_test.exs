defmodule AshyWalnutDesk.AI.Jobs.GenerationWorkerIdempotencyTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.AI.Jobs.GenerationWorker
  alias AshyWalnutDesk.Interaction.Draft
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

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Idempotency Persona",
          slug: "idempotency-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe prompt ", 8),
          disclosure_text: "AI-assisted draft.",
          guardrail_notes: nil,
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

  test "re-run on already-terminal draft is a no-op", %{draft: draft} do
    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 1,
               max_attempts: 3
             })

    completed = Ash.get!(Draft, draft.id, authorize?: false)
    assert completed.status == :drafting

    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 2,
               max_attempts: 3
             })

    reloaded = Ash.get!(Draft, draft.id, authorize?: false)
    assert reloaded.status == :drafting
    assert reloaded.updated_at == completed.updated_at
  end
end
