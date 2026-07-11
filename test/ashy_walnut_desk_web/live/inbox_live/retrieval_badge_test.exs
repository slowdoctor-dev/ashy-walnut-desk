defmodule AshyWalnutDeskWeb.InboxLive.RetrievalBadgeTest do
  @moduledoc """
  Story 5.6 AC3 — candidate cards carry `data-role="retrieval-badge"`
  with mode + excerpt count from `ai_retrieval`
  (`knowledge: 1 excerpts (vector)` / `knowledge: none`), and the badge
  is absent for drafts without `ai_retrieval` (pre-Phase-5 / manual
  compose path).
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.{Draft, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.{Manual, Persona}

  setup do
    prev_adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    Application.put_env(:ashy_walnut_desk, :ai_adapter, AshyWalnutDesk.AI.Adapters.Fixture)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :ai_adapter, prev_adapter) end)
    :ok
  end

  defp sign_in_as_admin(conn) do
    email = "retrieval-badge-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp seed_inbox_with_inbound(admin, operator) do
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

    inbox
  end

  defp create_persona!(admin) do
    Ash.create!(
      Persona,
      %{
        name: "Badge Persona",
        slug: "badge-persona-#{System.unique_integer([:positive])}",
        system_prompt: String.duplicate("safe prompt ", 8),
        disclosure_text: "AI-assisted draft."
      },
      action: :create,
      actor: admin
    )
  end

  defp generate!(inbox, persona, operator) do
    {:ok, draft} =
      Ash.create(Draft, %{inbox_id: inbox.id, persona_id: persona.id},
        action: :generate,
        actor: operator
      )

    Oban.drain_queue(queue: :ai_generation, with_recursion: true)
    draft
  end

  test "grounded candidate shows count + mode; ungrounded shows none; composed shows no badge",
       %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    operator = AshyWalnutDesk.AccountsFixtures.create_user(:operator)
    persona = create_persona!(admin)

    Ash.create!(
      Manual,
      %{
        title: "Scheduling",
        slug: "scheduling-badge-manual",
        body: "Appointment scheduling request: confirm the requested time first."
      },
      action: :author,
      actor: admin
    )

    Oban.drain_queue(queue: :knowledge_indexing, with_recursion: true)

    inbox = seed_inbox_with_inbound(admin, operator)
    generate!(inbox, persona, operator)
    composed = Fixtures.seed_draft(operator, inbox, body: "Composed by hand")

    {:ok, _view, html} = live(conn, ~p"/inbox/#{inbox.id}")

    assert html =~ "data-role=\"retrieval-badge\""
    assert html =~ "knowledge: 1 excerpts (vector)"

    # The hand-composed candidate renders a card but no badge.
    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=candidate-card]")
    assert length(rows) == 2

    composed_card =
      Enum.find(rows, fn row -> Floki.attribute(row, "id") == ["candidate-#{composed.id}"] end)

    assert composed_card
    assert Floki.find(composed_card, "[data-role=retrieval-badge]") == []
  end

  test "generation without any manuals shows knowledge: none", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    operator = AshyWalnutDesk.AccountsFixtures.create_user(:operator)
    persona = create_persona!(admin)
    inbox = seed_inbox_with_inbound(admin, operator)
    generate!(inbox, persona, operator)

    {:ok, _view, html} = live(conn, ~p"/inbox/#{inbox.id}")

    assert html =~ "data-role=\"retrieval-badge\""
    assert html =~ "knowledge: none"
  end
end
