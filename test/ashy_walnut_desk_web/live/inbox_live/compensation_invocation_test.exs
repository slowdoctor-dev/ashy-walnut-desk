defmodule AshyWalnutDeskWeb.InboxLive.CompensationInvocationTest do
  @moduledoc """
  Story 3.6 AC4 — operator can trigger a compensation from the
  Inbox chain view; the LV reflects the final outcome.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Interaction.Compensation
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  require Ash.Query
  import Ash.Expr

  defp sign_in_as(conn, role) do
    email = "comp-invoke-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "operator triggers compensation from chain view; status flips to :triggered", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)

    %{operator: chain_operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain()

    inbox_id = inbox.id

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, chain_operator)

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    assert render(view) =~ "Compensation follow-up"
    refute render(view) =~ "Sending in"

    view |> element("[data-role=trigger-compensation]") |> render_click()
    assert render(view) =~ "Sending in"

    :timer.sleep(5_500)

    Oban.drain_queue(queue: :outbound, with_recursion: true)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^action.id))
      |> Ash.read_one!()

    assert compensation.status == :triggered

    # The LV initiated the trigger and the worker drove the DB to
    # `:triggered`. Reloading the LV (simulating an operator
    # refresh — PubSub-driven live re-render is story 3.7+) shows
    # the outcome section.
    {:ok, fresh_view, _html} = live(conn, ~p"/inbox/#{inbox_id}")
    rendered = render(fresh_view)
    assert rendered =~ "Compensation outcome"
    assert rendered =~ "triggered"

    _ = view
  end

  test "trigger button is hidden before Action is :executed", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)

    %{inbox: inbox} = Fixtures.seed_approved_chain()

    {:ok, view, _html} = live(conn, ~p"/inbox/#{inbox.id}")

    refute render(view) =~ "Trigger compensation"
  end
end
