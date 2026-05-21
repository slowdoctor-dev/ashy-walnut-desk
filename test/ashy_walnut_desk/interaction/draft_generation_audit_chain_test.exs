defmodule AshyWalnutDesk.Interaction.DraftGenerationAuditChainTest do
  use AshyWalnutDesk.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{AuditEvent, Draft}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  setup do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    %{admin: admin, operator: operator, inbox: inbox}
  end

  test "generation requested/completed/failed events have expected payload shapes", %{
    admin: admin,
    operator: operator,
    inbox: inbox
  } do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, body: ""}, action: :generate, actor: operator)

    assert {:ok, _completed} =
             Ash.update(
               draft,
               %{
                 body: "Generated body",
                 ai_prompt: "prompt",
                 ai_model: "claude-sonnet-4-6",
                 ai_response: "Generated body",
                 ai_validator_output: %{
                   "passed?" => true,
                   "violations" => [],
                   "input_tokens" => 120,
                   "output_tokens" => 40,
                   "cache_read_tokens" => 12,
                   "cache_creation_tokens" => 0,
                   "baseline_version" => "base-v1",
                   "deployment_version" => "dep-v1"
                 }
               },
               action: :complete_generation,
               context: %{from_generation_worker: true}
             )

    {:ok, failed_draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, body: ""}, action: :generate, actor: operator)

    assert {:ok, _failed} =
             Ash.update(
               failed_draft,
               %{
                 ai_validator_output: %{
                   "error_class" => "provider_unavailable",
                   "error_detail_redacted" => "[redacted]"
                 }
               },
               action: :fail_generation,
               context: %{from_generation_worker: true}
             )

    events =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, actor: admin)
      |> Ash.Query.filter(expr(chain_topic == ^to_string(inbox.id)))
      |> Ash.Query.sort(inserted_at: :asc)
      |> Ash.read!(actor: admin)

    assert Enum.any?(events, &(&1.event_type == :draft_generation_requested))
    assert Enum.any?(events, &(&1.event_type == :draft_generation_completed))
    assert Enum.any?(events, &(&1.event_type == :draft_generation_failed))

    completed_event = Enum.find(events, &(&1.event_type == :draft_generation_completed))
    failed_event = Enum.find(events, &(&1.event_type == :draft_generation_failed))

    assert Map.has_key?(completed_event.payload, "validator_passed?")
    assert Map.has_key?(completed_event.payload, "violations_count")
    assert Map.has_key?(completed_event.payload, "baseline_version")
    assert Map.has_key?(completed_event.payload, "deployment_version")

    assert Map.has_key?(failed_event.payload, "error_class")
    assert Map.has_key?(failed_event.payload, "error_detail_redacted")
  end
end
