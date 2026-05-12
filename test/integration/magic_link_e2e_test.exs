defmodule AshyWalnutDesk.Integration.MagicLinkE2ETest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias AshyWalnutDesk.Accounts.User

  @first_email "phase-zero-admin@example.com"
  @second_email "phase-zero-operator@example.com"

  test "magic-link signup → email → sign-in → WelcomeLive sees the user; first user is admin, second is operator",
       %{conn: conn} do
    %{token: admin_token} = request_magic_link(conn, @first_email)
    admin_conn = complete_sign_in(conn, admin_token)
    assert_signed_in_at_welcome(admin_conn, @first_email)

    %{token: operator_token} = request_magic_link(build_conn(), @second_email)
    operator_conn = complete_sign_in(build_conn(), operator_token)
    assert_signed_in_at_welcome(operator_conn, @second_email)

    assert {:ok, %User{role: :admin}} = read_user(@first_email)
    assert {:ok, %User{role: :operator}} = read_user(@second_email)
  end

  defp request_magic_link(conn, email) do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    view
    |> form("form", %{"user" => %{"email" => email}})
    |> render_submit()

    parent = self()

    assert_email_sent(fn message ->
      if to_email_matches?(message, email) do
        token = message |> extract_magic_link_url() |> token_from_url()
        send(parent, {:magic_link_token, token})
        true
      end
    end)

    receive do
      {:magic_link_token, token} -> %{token: token}
    after
      0 -> raise "magic-link token never delivered for #{email}"
    end
  end

  defp complete_sign_in(conn, token) do
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == "/"
    recycle(conn)
  end

  defp assert_signed_in_at_welcome(conn, email) do
    {:ok, view, _html} = live(conn, ~p"/")
    rendered = render(view)
    assert rendered =~ "Signed in as"
    assert rendered =~ email
    assert has_element?(view, "a[href='/sign-out']", "Sign out")
  end

  defp read_user(email) do
    case Ash.read(User, action: :read, authorize?: false) do
      {:ok, users} ->
        Enum.find(users, &(to_string(&1.email) == email))
        |> case do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      other ->
        other
    end
  end

  defp extract_magic_link_url(message) do
    body = (message.html_body || "") <> "\n" <> (message.text_body || "")

    Regex.run(~r{https?://[^\s"<>]+/auth/user/magic_link[^\s"<>]*}, body)
    |> case do
      [url] -> url
      _ -> raise "no magic-link URL in email body: #{body}"
    end
  end

  defp token_from_url(url) do
    %URI{query: query} = URI.parse(url)

    case query && URI.decode_query(query) do
      %{"token" => token} -> token
      _ -> raise "magic-link URL has no token query param: #{url}"
    end
  end

  defp to_email_matches?(message, email) do
    Enum.any?(List.wrap(message.to), fn {_name, to} -> to_string(to) == email end)
  end
end
