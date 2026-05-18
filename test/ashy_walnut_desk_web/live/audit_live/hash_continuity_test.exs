defmodule AshyWalnutDeskWeb.AuditLive.HashContinuityTest do
  @moduledoc """
  Story 3.7 AC3 — each row's continuity status (computed locally,
  matching `mix audit.verify` semantics) is rendered as `:ok` for
  every row in an intact chain.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  defp sign_in_as_admin(conn) do
    email = "hash-admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: :admin}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: :admin}, action: :assign_role, authorize?: false)
    {recycle(conn), user}
  end

  test "intact chain renders all rows with :ok status badge", %{conn: conn} do
    {conn, admin} = sign_in_as_admin(conn)

    %{operator: operator, draft: draft, inbox: inbox, action: action} =
      Fixtures.seed_approved_chain(admin: admin)

    Fixtures.backdate_approval!(draft, 6)
    _executed = Fixtures.execute_action!(action, operator)

    {:ok, _view, html} = live(conn, ~p"/audit/chain?topic=#{inbox.id}")

    # All 6 events report status `:ok`.
    rows = Floki.parse_fragment!(html) |> Floki.find("[data-role=audit-row]")
    assert length(rows) == 6

    Enum.each(rows, fn row ->
      assert Floki.attribute(row, "data-status") == ["ok"]
    end)
  end
end
