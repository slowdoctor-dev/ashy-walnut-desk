defmodule AshyWalnutDesk.AI.Jobs.GenerationWorkerTelemetryTest do
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
          name: "Telemetry Persona",
          slug: "telemetry-persona-#{System.unique_integer([:positive])}",
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

    handler_id = "generation-worker-telemetry-#{System.unique_integer([:positive])}"

    parent = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:awd, :ai, :generation, :start],
          [:awd, :ai, :generation, :stop],
          [:awd, :ai, :validator, :stop]
        ],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    %{draft: draft}
  end

  test "worker emits generation and validator telemetry", %{draft: draft} do
    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 1,
               max_attempts: 3
             })

    assert_receive {:telemetry_event, [:awd, :ai, :generation, :start], _, start_meta}
    assert start_meta.draft_id == draft.id

    assert_receive {:telemetry_event, [:awd, :ai, :generation, :stop], stop_measurements,
                    stop_meta}

    assert stop_measurements.duration > 0
    assert stop_measurements.input_tokens >= 0
    assert stop_measurements.output_tokens >= 0
    assert stop_measurements.cache_read_tokens >= 0
    assert stop_measurements.cache_creation_tokens >= 0
    assert stop_meta.draft_id == draft.id

    assert_receive {:telemetry_event, [:awd, :ai, :validator, :stop], validator_measurements,
                    validator_meta}

    assert validator_measurements.duration > 0
    assert is_boolean(validator_meta["passed?"] || validator_meta.passed?)
    assert validator_meta.draft_id == draft.id
  end
end
