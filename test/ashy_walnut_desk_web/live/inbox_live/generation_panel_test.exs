defmodule AshyWalnutDeskWeb.InboxLive.GenerationPanelTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.Draft
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Knowledge.Persona

  defp sign_in_as(conn, role) do
    email = "inbox-generation-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp create_persona(admin) do
    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Default Persona",
          slug: "default-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe prompt ", 8),
          disclosure_text: "AI-assisted draft.",
          guardrail_notes: "Keep claims factual.",
          model_override: nil,
          status: :active
        },
        action: :create,
        actor: admin
      )

    persona
  end

  test "operator can generate and sees generating candidate card", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    {_operator_conn, operator} = sign_in_as(build_conn(), :operator)

    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)
    persona = create_persona(admin)

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    html =
      view
      |> form("#generation-form", %{"generation_form" => %{"persona_id" => persona.id}})
      |> render_submit()

    assert html =~ "Generating draft"
    assert html =~ "Status: generating"

    drafts = Ash.read!(Draft, authorize?: false)
    assert Enum.any?(drafts, &(&1.inbox_id == inbox.id and &1.status == :generating))
  end
end
