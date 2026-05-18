defmodule AshyWalnutDeskWeb.InboxLive.ShowTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.{Action, Compensation, Draft}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  require Ash.Query

  defp sign_in_as(conn, role) do
    email = "inbox-show-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "compose, revise, approve, countdown, execute", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    {_admin_conn, admin} = sign_in_as(build_conn(), :admin)

    identity = Fixtures.seed_identity(admin, display_name: "Case", primary_identifier: "+155503")
    channel = Fixtures.seed_channel(admin)

    conversation =
      Fixtures.seed_conversation(operator, identity, channel, subject: "Need callback")

    inbox = Fixtures.seed_inbox(operator, conversation, summary: "Need callback")

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    html =
      view
      |> form("#draft-form", %{
        "draft_form" => %{"body" => "First draft", "compensation_body" => "Offer follow-up"}
      })
      |> render_submit()

    assert html =~ "First draft"

    view |> element("[data-role=approve-draft]") |> render_click()

    assert render(view) =~ "Sending in"

    :timer.sleep(5500)

    # Story 3.5: drain the Oban outbound queue (ADR-023).
    Oban.drain_queue(queue: :outbound, with_recursion: true)

    action =
      Action
      |> Ash.Query.filter(draft_id in ^draft_ids_for_inbox(inbox.id))
      |> Ash.read_one!(authorize?: false)

    assert action.status == :executed

    draft = Draft |> Ash.Query.filter(inbox_id == ^inbox.id) |> Ash.read_one!(authorize?: false)

    compensation =
      Compensation
      |> Ash.Query.filter(action_id == ^action.id)
      |> Ash.read_one!(authorize?: false)

    assert draft.status == :approved
    assert compensation.status == :registered
  end

  defp draft_ids_for_inbox(inbox_id) do
    Draft
    |> Ash.Query.filter(inbox_id == ^inbox_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
