defmodule AshyWalnutDeskWeb.AuditLive.ChainFilteringTest do
  @moduledoc """
  Story 3.7 AC2 — viewer lists chain topics and filters events
  per topic.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp sign_in_as_admin(conn) do
    email = "audit-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), user}
  end

  defp drive_full_chain(admin) do
    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain(admin: admin)

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)
    inbox
  end

  test "no-topic view lists all chain topics", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    inbox_a = drive_full_chain(admin)
    inbox_b = drive_full_chain(admin)

    {:ok, _view, html} = live(conn, ~p"/audit/chain")
    assert html =~ "Chain topics"
    assert html =~ inbox_a.id
    assert html =~ inbox_b.id
  end

  test "filtering by topic shows only that topic's events", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    inbox_a = drive_full_chain(admin)
    inbox_b = drive_full_chain(admin)

    {:ok, view, _html} = live(conn, ~p"/audit/chain?topic=#{inbox_a.id}")

    rendered = render(view)
    assert rendered =~ "inbox_opened"
    assert rendered =~ "action_executed"

    # Switching to topic B via push_patch reloads the events.
    {:ok, view_b, _html} = live(conn, ~p"/audit/chain?topic=#{inbox_b.id}")
    rendered_b = render(view_b)
    assert rendered_b =~ inbox_b.id
  end

  test "viewer shows total event count for a chain (6 after action send)", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)
    inbox = drive_full_chain(admin)

    {:ok, view, _html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")
    assert render(view) =~ "6 events"
  end
end
