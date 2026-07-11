defmodule AshyWalnutDesk.Integration.Phase5KnowledgeRagE2ETest do
  @moduledoc """
  Story 5.7 AC3/AC4 — end-to-end Phase 5 pipeline:

  1. Admin authors a Manual → `:knowledge_indexing` drains → chunks
     embedded (Fixture embedder). (Stories 5.1–5.3)
  2. Operator generates a draft → Retriever grounds the prompt
     (`mode: :vector`), provenance persists on `Draft.ai_retrieval`,
     the operator-facing badge renders. (Stories 5.4–5.6)
  3. No autonomous send: approval still requires the ValidatorPassed
     gate + explicit human action, and execute before the 5-second
     countdown is refused (ADR-005/ADR-013).
  4. After the countdown, the send completes and the hash-chained audit
     trail (including the extended `:draft_generation_completed`
     payload with retrieval fields) walks clean and renders all-`:ok`
     in the admin LiveView. (ADR-016)

  Both AI provider and embeddings are deterministic fixtures — no
  network calls.
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
  alias AshyWalnutDesk.Knowledge.{Manual, Persona}

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    Application.put_env(:ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter) end)
    :ok
  end

  defp sign_in_as_admin(conn) do
    email = "phase5-e2e-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "author → index → retrieve → generate → approve → countdown → send, audited",
       %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    operator = AshyWalnutDesk.AccountsFixtures.create_user(:operator)

    # ─── 1. Knowledge: author + index a Manual ───────────────────────
    manual =
      Ash.create!(
        Manual,
        %{
          title: "Scheduling manual",
          slug: "phase5-scheduling-manual",
          body: "Appointment scheduling request: confirm the requested time first."
        },
        action: :author,
        actor: admin
      )

    assert %{success: 1} = Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    # ─── 2. Interaction bootstrap + grounded generation ──────────────
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
          name: "Phase 5 E2E Persona",
          slug: "phase5-e2e-persona",
          system_prompt: String.duplicate("safe framework prompt ", 8),
          disclosure_text: "AI-assisted draft; reviewed by a human operator."
        },
        action: :create,
        actor: admin
      )

    {:ok, generating} =
      Ash.create(Draft, %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: operator
      )

    Oban.drain_queue(queue: :ai_generation, with_recursion: true)
    draft = Ash.get!(Draft, generating.id, authorize?: false)

    assert draft.status == :drafting
    assert draft.ai_validator_output["passed?"] == true
    assert draft.ai_retrieval["mode"] == "vector"
    assert [excerpt] = draft.ai_retrieval["excerpts"]
    assert excerpt["manual_id"] == manual.id
    assert excerpt["manual_slug"] == manual.slug
    assert excerpt["revision"] == 1
    assert draft.ai_prompt =~ "[Deployment Knowledge]"

    # Operator-facing provenance badge (story 5.6).
    {:ok, _view, inbox_html} = live(conn, ~p"/inbox/#{inbox.id}")
    assert inbox_html =~ "data-role=\"retrieval-badge\""
    assert inbox_html =~ "knowledge: 1 excerpts (vector)"

    # ─── 3. Approve; countdown refuses an early execute ──────────────
    {:ok, approved} =
      Ash.update(draft, %{compensation_body: "Follow-up if no reply in 2 days"},
        action: :approve,
        actor: operator
      )

    action =
      Action
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!()

    assert {:error, %Ash.Error.Invalid{} = countdown_error} =
             Ash.update(action, %{}, action: :execute, actor: operator)

    assert Exception.message(countdown_error) =~ "countdown_violation"

    # ─── 4. Countdown elapsed → send ─────────────────────────────────
    approved = Fixtures.backdate_approval!(approved, 6)
    executed_action = Fixtures.execute_action!(action, operator)
    assert executed_action.status == :executed

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(conversation_id == ^conversation.id and direction == :outbound))
      |> Ash.read!(authorize?: false)

    assert [sent] = outbound
    assert sent.body == approved.body

    # ─── 5. Audit chain with retrieval fields, all-:ok ───────────────
    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))

    assert Enum.map(events, & &1.event_type) == [
             :inbox_opened,
             :draft_generation_requested,
             :draft_generation_completed,
             :draft_approved,
             :compensation_registered,
             :action_scheduled,
             :action_executed
           ]

    completed_event = Enum.find(events, &(&1.event_type == :draft_generation_completed))
    assert completed_event.payload["retrieval_mode"] == "vector"
    assert completed_event.payload["retrieval_chunk_count"] == 1

    {:ok, _view, html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")
    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=audit-row]")
    assert length(rows) == 7
    assert Enum.all?(rows, fn row -> Floki.attribute(row, "data-status") == ["ok"] end)
  end
end
