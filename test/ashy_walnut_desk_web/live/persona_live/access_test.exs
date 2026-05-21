defmodule AshyWalnutDeskWeb.PersonaLive.AccessTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Knowledge.Persona

  defp sign_in_as(conn, role) do
    email = "persona-access-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(User, %{email: email, role: role}, action: :register, authorize?: false)

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    {:ok, _} = Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)

    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  test "unauthenticated user is redirected to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/personas")
  end

  test "operator is redirected from admin-only routes", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)

    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/personas")
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/personas/new")
  end

  test "admin can access index and form", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)

    {:ok, persona} =
      Ash.create(
        Persona,
        %{
          name: "Admin Persona",
          slug: "admin-persona",
          system_prompt: String.duplicate("Z", 64),
          disclosure_text: "Generated with AI assistance."
        },
        action: :create,
        actor: admin
      )

    assert {:ok, _view, index_html} = live(conn, ~p"/personas")
    assert index_html =~ "Personas"
    assert index_html =~ "admin-persona"

    assert {:ok, _view, new_html} = live(conn, ~p"/personas/new")
    assert new_html =~ "New persona"

    assert {:ok, _view, edit_html} = live(conn, ~p"/personas/#{persona.id}/edit")
    assert edit_html =~ "Edit persona"
  end
end
