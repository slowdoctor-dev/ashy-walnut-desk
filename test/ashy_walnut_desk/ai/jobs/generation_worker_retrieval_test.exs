defmodule AshyWalnutDesk.AI.Jobs.GenerationWorkerRetrievalTest do
  @moduledoc """
  Story 5.5 AC2/AC4 — the worker retrieves before assembly, persists
  `ai_retrieval` provenance (no excerpt text) on `:complete_generation`,
  embeds excerpt text into `ai_prompt`, and with `:retrieval` disabled
  behaves exactly like Phase 4 (mode "none", zero excerpts).
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.AI.Jobs.GenerationWorker
  alias AshyWalnutDesk.Interaction.{Draft, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.{Manual, Persona}

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    prev_retrieval = Application.get_env(:ashy_walnut_desk, :retrieval)
    Application.put_env(:ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture)

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter)
      Application.put_env(:ashy_walnut_desk, :retrieval, prev_retrieval)
    end)

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
          body: "Please confirm my appointment scheduling request time."
        },
        action: :record_message,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Retrieval Persona",
          slug: "retrieval-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe prompt ", 8),
          disclosure_text: "AI-assisted draft."
        },
        action: :create,
        actor: admin
      )

    manual =
      Ash.create!(
        Manual,
        %{
          title: "Scheduling manual",
          slug: "scheduling-manual-#{System.unique_integer([:positive])}",
          body: "Appointment scheduling request: confirm the requested time first."
        },
        action: :author,
        actor: admin
      )

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: operator
      )

    %{draft: draft, manual: manual}
  end

  defp run_worker!(draft) do
    assert :ok =
             GenerationWorker.perform(%Oban.Job{
               args: %{"draft_id" => draft.id},
               attempt: 1,
               max_attempts: 3
             })

    Ash.get!(Draft, draft.id, authorize?: false)
  end

  test "persists retrieval provenance and grounds the prompt", %{draft: draft, manual: manual} do
    reloaded = run_worker!(draft)

    assert reloaded.status == :drafting
    assert reloaded.ai_retrieval["mode"] == "vector"
    assert [excerpt] = reloaded.ai_retrieval["excerpts"]
    assert excerpt["manual_id"] == manual.id
    assert excerpt["manual_slug"] == manual.slug
    assert excerpt["revision"] == 1
    assert excerpt["embedder"] == "fixture"
    assert is_number(excerpt["score"])
    # Provenance carries no excerpt text — that lives in ai_prompt.
    refute Map.has_key?(excerpt, "content")

    assert reloaded.ai_prompt =~ "[Deployment Knowledge]"
    assert reloaded.ai_prompt =~ "confirm the requested time first"
  end

  test "retrieval disabled reproduces Phase 4 behavior", %{draft: draft} do
    Application.put_env(:ashy_walnut_desk, :retrieval, enabled?: false)

    reloaded = run_worker!(draft)

    assert reloaded.status == :drafting
    assert reloaded.ai_retrieval["mode"] == "none"
    assert reloaded.ai_retrieval["excerpts"] == []
    refute reloaded.ai_prompt =~ "[Deployment Knowledge]"
  end
end
