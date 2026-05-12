defmodule AshyWalnutDeskWeb.WelcomeLiveTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink

  test "renders project name, version, and sign-in link for guests", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    rendered = render(view)

    assert rendered =~ "ashy-walnut-desk"
    assert rendered =~ to_string(Application.spec(:ashy_walnut_desk, :vsn))
    assert has_element?(view, "a[href='/sign-in']", "Sign in")
  end

  test "renders current user email and sign-out link for authenticated users", %{conn: conn} do
    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, "welcome-live-user@example.com")

    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == "/"

    conn = recycle(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    rendered = render(view)
    assert rendered =~ "Signed in as"
    assert rendered =~ "welcome-live-user@example.com"
    assert has_element?(view, "a[href='/sign-out']", "Sign out")
  end
end
