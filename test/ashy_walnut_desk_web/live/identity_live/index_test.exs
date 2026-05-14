defmodule AshyWalnutDeskWeb.IdentityLive.IndexTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity

  defp sign_in_as(conn, role) do
    email = "identity-index-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(
        User,
        %{email: email, role: role},
        action: :register,
        authorize?: false
      )

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

    # sign_in_with_magic_link runs AssignFirstUserAdmin, which overrides
    # the role. Restore the desired role server-side so the LiveView
    # observes the test-intended role on its next mount.
    {:ok, _} =
      Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)

    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp register_identity(actor, attrs) do
    Ash.create!(
      Identity,
      Map.merge(
        %{
          display_name: "Subject #{System.unique_integer([:positive])}",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        attrs
      ),
      action: :register_identity,
      actor: actor
    )
  end

  # AC1 — Index renders for authenticated actors and lists non-archived identities

  test "redirects guests to sign-in", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/identities")
    assert to =~ "/sign-in"
  end

  test "operator sees their identities listed by default", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    identity = register_identity(operator, %{display_name: "Alpha"})

    {:ok, _view, html} = live(conn, ~p"/identities")

    assert html =~ "Identities"
    assert html =~ "Alpha"
    assert html =~ "identity-#{identity.id}"
  end

  test "viewer sees the index but no new-identity affordance", %{conn: conn} do
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)
    register_identity(admin, %{display_name: "Bravo"})
    _ = admin_conn

    {conn, _viewer} = sign_in_as(conn, :viewer)

    {:ok, view, html} = live(conn, ~p"/identities")

    assert html =~ "Bravo"
    refute has_element?(view, "[data-role=new-identity]")
  end

  # AC4 — Archive/recover UX behavior

  test "archived identities are hidden from default index", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    visible = register_identity(operator, %{display_name: "Visible"})
    archived = register_identity(operator, %{display_name: "Hidden"})

    {:ok, _archived} = Ash.update(archived, %{}, action: :archive, actor: operator)

    {:ok, view, _html} = live(conn, ~p"/identities")

    assert has_element?(view, "#identity-#{visible.id}")
    refute has_element?(view, "#identity-#{archived.id}")
  end

  test "admin can toggle archived view to see archived identities", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    archived = register_identity(admin, %{display_name: "Resurrectable"})
    {:ok, _} = Ash.update(archived, %{}, action: :archive, actor: admin)

    {:ok, view, _html} = live(conn, ~p"/identities")

    refute has_element?(view, "#identity-#{archived.id}")
    assert has_element?(view, "[data-role=toggle-archived]")

    html = view |> element("[data-role=toggle-archived]") |> render_click()

    assert html =~ "identity-#{archived.id}"
    assert html =~ "Resurrectable"
    assert has_element?(view, "[data-role=archived-badge]")
  end

  test "operator does not see the archived toggle", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)

    {:ok, view, _html} = live(conn, ~p"/identities")

    refute has_element?(view, "[data-role=toggle-archived]")
  end
end
