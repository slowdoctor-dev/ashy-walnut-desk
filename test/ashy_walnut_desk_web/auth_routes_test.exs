defmodule AshyWalnutDeskWeb.AuthRoutesTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink

  test "GET /sign-in renders the magic-link email form", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")

    assert html_response(conn, 200) =~ ~s(type="email")
  end

  test "GET /magic_link/:token renders a confirm form carrying _csrf_token", %{conn: conn} do
    # Regression guard for the bug shipped in c3a5028: the email used to
    # point at /auth/user/magic_link, which served an upstream EEx fallback
    # form with no CSRF input. The MagicSignInLive form must include it.
    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, "csrf-shape-test@example.com")

    conn = get(conn, ~p"/magic_link/#{token}")
    html = html_response(conn, 200)

    assert html =~ ~s(name="_csrf_token")
    assert html =~ ~s(action="/auth/user/magic_link)
  end

  test "submitting the sign-in form sends a magic-link email", %{conn: conn} do
    email = "magic-link-user@example.com"

    {:ok, view, _html} = live(conn, ~p"/sign-in")

    view
    |> form("form", %{"user" => %{"email" => email}})
    |> render_submit()

    assert_email_sent(fn message ->
      body = (message.html_body || "") <> (message.text_body || "")

      String.downcase(to_string(message.subject || "")) =~ "magic" and
        Enum.any?(List.wrap(message.to), fn {_name, to_email} ->
          to_string(to_email) == email
        end) and
        String.contains?(body, "/magic_link/")
    end)
  end
end
