defmodule AshyWalnutDesk.Integration.Phase4AiDraftChainE2ETest do
  @moduledoc """
  Story 4.8 AC3/AC4 — end-to-end integration covering the full Phase 4
  pipeline:

  1. Operator requests generation (`Draft.:generate`) against an open
     Inbox with a Persona → `GenerationWorker` (drained inline) calls
     the Fixture adapter, runs the validator stack, persists provenance
     (`ai_prompt`/`ai_model`/`ai_response`/`ai_validator_output`), and
     appends the Persona disclosure footer. (Stories 4.1–4.6)
  2. A second candidate is generated; approving it auto-supersedes the
     first (Q5 multi-candidate semantics). (Story 4.5)
  3. No autonomous send: generation alone creates no Action and no
     outbound Message; a validator-failed draft cannot be approved
     (`ValidatorPassed`); an approved draft cannot execute before the
     server-side 5-second countdown elapses (`CountdownGuard`,
     ADR-013).
  4. After the countdown, `Action.:execute` → `Jobs.OutboundSend` →
     stub adapter → outbound Message; the hash-chained audit trail
     walks clean end to end and renders all-`:ok` in the admin
     LiveView. (ADR-016)

  Provider is the deterministic Fixture adapter — no network calls.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  require Ash.Query
  import Ash.Expr

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User

  alias AshyWalnutDesk.Interaction.{
    Action,
    AuditChain,
    Draft,
    Message
  }

  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.Persona

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    Application.put_env(:ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter) end)
    :ok
  end

  defp sign_in_as_admin(conn) do
    email = "phase4-e2e-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp create_persona(admin) do
    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Phase 4 E2E Persona",
          slug: "phase4-e2e-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe framework prompt ", 8),
          disclosure_text: "AI-assisted draft; reviewed by a human operator.",
          guardrail_notes: "No unsupported claims.",
          model_override: "claude-sonnet-4-6"
        },
        action: :create,
        actor: admin
      )

    persona
  end

  defp generate_candidate!(inbox, persona, operator) do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: operator
      )

    assert draft.status == :generating

    Oban.drain_queue(queue: :ai_generation, with_recursion: true)
    Ash.get!(Draft, draft.id, authorize?: false)
  end

  defp messages(conversation_id, direction) do
    Message
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.Query.filter(expr(conversation_id == ^conversation_id and direction == ^direction))
    |> Ash.read!(authorize?: false)
  end

  test "generate → validate → approve → countdown → send, with no autonomous-send bypass",
       %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    operator = AshyWalnutDesk.AccountsFixtures.create_user(:operator)

    # ─── 1. Bootstrap: identity/channel/conversation/inbox + persona ─
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)
    persona = create_persona(admin)

    {:ok, _inbound} =
      Ash.create(
        Message,
        %{
          conversation_id: conversation.id,
          direction: :inbound,
          body: "Can you confirm my appointment for tomorrow?"
        },
        action: :record_message,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    # ─── 2. Generation: two candidates through the worker ───────────
    candidate_a = generate_candidate!(inbox, persona, operator)
    candidate_b = generate_candidate!(inbox, persona, operator)

    for candidate <- [candidate_a, candidate_b] do
      assert candidate.status == :drafting
      assert candidate.ai_model == "claude-sonnet-4-6"
      assert is_binary(candidate.ai_prompt)
      assert is_binary(candidate.ai_response)
      assert candidate.ai_validator_output["passed?"] == true
      assert String.ends_with?(candidate.body, persona.disclosure_text)
    end

    # ─── 3. No autonomous send: generation created no send-side state ─
    action_count =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.count!(authorize?: false)

    assert action_count == 0
    assert messages(conversation.id, :outbound) == []

    # A validator-failed candidate is reviewable but not approvable
    # (ValidatorPassed gate). Staged on a separate inbox so the main
    # audit chain stays canonical.
    blocked_inbox = Fixtures.seed_inbox(operator, conversation, summary: "Validator-fail lane")

    blocked_draft =
      Fixtures.seed_draft(operator, blocked_inbox,
        body: "We guarantee full recovery in two days.",
        ai_model: "claude-sonnet-4-6",
        ai_response: "We guarantee full recovery in two days.",
        ai_validator_output: %{"passed?" => false, "violations" => [%{"rule" => "baseline"}]}
      )

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.update(blocked_draft, %{compensation_body: "Follow-up"},
               action: :approve,
               actor: operator
             )

    # ─── 4. Approval: candidate B wins, sibling A superseded ────────
    {:ok, approved} =
      Ash.update(candidate_b, %{compensation_body: "Follow-up if no reply in 2 days"},
        action: :approve,
        actor: operator
      )

    assert approved.status == :approved
    assert Ash.get!(Draft, candidate_a.id, authorize?: false).status == :superseded

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!()

    # ─── 5. Countdown gate: execute before 5s is refused (ADR-013) ──
    assert {:error, %Ash.Error.Invalid{} = countdown_error} =
             Ash.update(action, %{}, action: :execute, actor: operator)

    assert Exception.message(countdown_error) =~ "countdown_violation"
    assert messages(conversation.id, :outbound) == []

    # ─── 6. Countdown elapsed → execute → outbound send ─────────────
    approved = Fixtures.backdate_approval!(approved, 6)
    executed_action = Fixtures.execute_action!(action, operator)
    assert executed_action.status == :executed

    assert length(messages(conversation.id, :inbound)) == 1
    assert [outbound] = messages(conversation.id, :outbound)
    assert outbound.body == approved.body
    assert String.ends_with?(outbound.body, persona.disclosure_text)

    # ─── 7. Audit chain: hash-linked, complete, and admin-visible ───
    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))

    assert Enum.map(events, & &1.event_type) == [
             :inbox_opened,
             :draft_generation_requested,
             :draft_generation_completed,
             :draft_generation_requested,
             :draft_generation_completed,
             :draft_superseded,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed
           ]

    approved_event = Enum.find(events, &(&1.event_type == :draft_approved))
    assert approved_event.payload["superseded_sibling_draft_ids"] == [candidate_a.id]

    completed_event = Enum.find(events, &(&1.event_type == :draft_generation_completed))
    assert completed_event.payload["validator_passed?"] == true

    {:ok, _view, html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")
    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=audit-row]")
    assert length(rows) == 10
    assert Enum.all?(rows, fn row -> Floki.attribute(row, "data-status") == ["ok"] end)
  end
end
