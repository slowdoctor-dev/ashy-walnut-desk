defmodule AshyWalnutDeskWeb.InboxLive.CandidateFlowTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Ash.Expr
  import Phoenix.LiveViewTest
  require Ash.Query

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.{Action, Draft}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp sign_in_as(conn, role) do
    email = "inbox-candidate-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "failed validator candidate disables approve while regenerate/reject remain enabled", %{
    conn: conn
  } do
    {conn, admin} = sign_in_as(conn, :admin)
    {_operator_conn, operator} = sign_in_as(build_conn(), :operator)

    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    {:ok, failed} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "bad draft",
          compensation_body: "comp",
          status: :drafting,
          ai_validator_output: %{
            "passed?" => false,
            "violations" => [%{"code" => "honest_framing"}]
          }
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    assert has_element?(view, "[data-role='approve-candidate-#{failed.id}'][disabled]")
    assert has_element?(view, "[data-role='reject-candidate-#{failed.id}']")
    assert has_element?(view, "[data-role='regenerate-candidate-#{failed.id}']")
  end

  test "approving one candidate supersedes siblings and removes stale cards", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    {_operator_conn, operator} = sign_in_as(build_conn(), :operator)

    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    {:ok, first} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "first candidate",
          compensation_body: "first comp",
          status: :drafting,
          ai_validator_output: %{"passed?" => true, "violations" => []}
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, second} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "second candidate",
          compensation_body: "second comp",
          status: :drafting,
          ai_validator_output: %{"passed?" => true, "violations" => []}
        },
        action: :compose_draft,
        actor: operator
      )

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    view
    |> element("[data-role='approve-candidate-#{second.id}']")
    |> render_click()

    assert render(view) =~ "Sending in"
    refute has_element?(view, "#candidate-#{first.id}")
    refute has_element?(view, "#candidate-#{second.id}")

    approved = Ash.get!(Draft, second.id, authorize?: false)
    superseded = Ash.get!(Draft, first.id, authorize?: false)
    assert approved.status == :approved
    assert superseded.status == :superseded

    action =
      Action
      |> Ash.Query.filter(expr(draft_id == ^approved.id))
      |> Ash.read_one!(authorize?: false)

    assert action.status in [:pending, :scheduled]
  end
end
