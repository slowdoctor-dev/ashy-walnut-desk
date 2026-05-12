defmodule AshyWalnutDeskWeb.AuthRoutesTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  test "GET /sign-in renders the magic-link email form", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")

    assert html_response(conn, 200) =~ ~s(type="email")
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
