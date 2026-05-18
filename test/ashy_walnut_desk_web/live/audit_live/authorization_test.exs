defmodule AshyWalnutDeskWeb.AuditLive.AuthorizationTest do
  @moduledoc """
  Story 3.7 AC1 — `/audit/chain` is admin-only. Non-admin
  authenticated users (operator, viewer) are redirected; unauth'd
  visitors are redirected to sign-in.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User

  defp sign_in_as(conn, role) do
    email = "audit-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "unauthenticated user is redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/audit/chain")
  end

  test "operator role is redirected (not admin)", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/audit/chain")
  end

  test "viewer role is redirected (not admin)", %{conn: conn} do
    {conn, _viewer} = sign_in_as(conn, :viewer)
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/audit/chain")
  end

  test "admin can load the chain viewer", %{conn: conn} do
    {conn, _admin} = sign_in_as(conn, :admin)
    assert {:ok, _view, html} = live(conn, ~p"/audit/chain")
    assert html =~ "Audit chain"
  end
end
