defmodule AshyWalnutDeskWeb.ManualLive.IndexTest do
  @moduledoc """
  Story 5.6 AC1 — `/manuals` is admin-only, lists title/slug/status/
  revision, and supports archive/restore inline.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Knowledge.Manual

  defp sign_in_as(conn, role) do
    email = "manual-index-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)
    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp author!(admin, slug) do
    Ash.create!(
      Manual,
      %{title: "Manual #{slug}", slug: slug, body: "Reference content for #{slug}."},
      action: :author,
      actor: admin
    )
  end

  test "unauthenticated and non-admin users are redirected", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/manuals")

    {operator_conn, _} = sign_in_as(build_conn(), :operator)
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(operator_conn, ~p"/manuals")

    {viewer_conn, _} = sign_in_as(build_conn(), :viewer)
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(viewer_conn, ~p"/manuals")
  end

  test "admin sees title, slug, and revision", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    manual = author!(admin, "front-desk-guide")
    {:ok, _} = Ash.update(manual, %{body: "Revised."}, action: :revise, actor: admin)

    {:ok, _view, html} = live(conn, ~p"/manuals")

    assert html =~ "front-desk-guide"
    assert html =~ "Manual front-desk-guide"
    assert html =~ ~r/revision\s*2/
  end

  test "archive and restore flow from the list", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    manual = author!(admin, "archivable-guide")

    {:ok, view, _html} = live(conn, ~p"/manuals")

    html =
      view
      |> element("[data-role='archive-manual-#{manual.id}']")
      |> render_click()

    # Archived-but-not-deleted rows stay listed with a badge.
    assert html =~ "data-role=\"archived-badge\""

    html =
      view
      |> element("[data-role='restore-manual-#{manual.id}']")
      |> render_click()

    refute html =~ "data-role=\"archived-badge\""
    assert Ash.get!(Manual, manual.id, actor: admin).status == :active
  end
end
