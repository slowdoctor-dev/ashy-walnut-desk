defmodule AshyWalnutDesk.AI.Jobs.GenerationWorkerFailureTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.AI.Jobs.GenerationWorker
  alias AshyWalnutDesk.Interaction.{Action, Draft}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.Persona

  defmodule TransientAdapter do
    @behaviour AshyWalnutDesk.AI.Adapter
    def complete(_prompt, _opts), do: {:error, :transient}
  end

  defmodule PermanentAdapter do
    @behaviour AshyWalnutDesk.AI.Adapter
    def complete(_prompt, _opts), do: {:error, :permanent}
  end

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    prev_allowlist = Application.get_env(:ashy_walnut_desk, :ai_adapter_allowlist)

    Application.put_env(:ashy_walnut_desk, :ai_adapter_allowlist, [
      TransientAdapter,
      PermanentAdapter
    ])

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter)
      Application.put_env(:ashy_walnut_desk, :ai_adapter_allowlist, prev_allowlist)
    end)

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
          name: "Failure Persona",
          slug: "failure-persona-#{System.unique_integer([:positive])}",
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

    %{draft: draft, admin: admin}
  end

  test "transient errors raise for Oban retry", %{draft: draft} do
    Application.put_env(:ashy_walnut_desk, :ai_adapter, TransientAdapter)

    assert_raise RuntimeError, "generation transient failure", fn ->
      GenerationWorker.perform(%Oban.Job{
        args: %{"draft_id" => draft.id},
        attempt: 1,
        max_attempts: 3
      })
    end

    reloaded = Ash.get!(Draft, draft.id, authorize?: false)
    assert reloaded.status == :generating
  end

  test "permanent errors terminal-fail draft and do not mutate send-stage records", %{
    draft: draft,
    admin: admin
  } do
    Application.put_env(:ashy_walnut_desk, :ai_adapter, PermanentAdapter)

    approved = Fixtures.seed_approved_chain(admin: admin)
    action_before = Ash.get!(Action, approved.action.id, authorize?: false)

    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 1,
               max_attempts: 3
             })

    failed = Ash.get!(Draft, draft.id, authorize?: false)
    assert failed.status == :rejected
    assert failed.ai_validator_output["error_class"] == "provider_permanent"

    action_after = Ash.get!(Action, approved.action.id, authorize?: false)
    assert action_after.status == action_before.status
    assert action_after.id == action_before.id
  end
end
