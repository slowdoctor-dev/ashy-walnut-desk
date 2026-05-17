defmodule AshyWalnutDeskWeb.EndpointSessionCookieTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink

  test "prod-like session options set Secure+HttpOnly on auth cookie", %{conn: conn} do
    with_session_options([secure: true, http_only: true], fn ->
      conn = sign_in_with_magic_link(conn, "cookie-prod-like@example.com")
      cookies = get_resp_header(conn, "set-cookie")
      cookies_downcased = Enum.map(cookies, &String.downcase/1)

      assert Enum.any?(cookies, &String.contains?(&1, "_ashy_walnut_desk_key="))
      assert Enum.any?(cookies_downcased, &String.contains?(&1, "secure"))
      assert Enum.any?(cookies_downcased, &String.contains?(&1, "httponly"))
    end)
  end

  test "dev-like session options do not set Secure on auth cookie", %{conn: conn} do
    with_session_options([secure: false], fn ->
      conn = sign_in_with_magic_link(conn, "cookie-dev-like@example.com")
      cookies = get_resp_header(conn, "set-cookie")
      cookies_downcased = Enum.map(cookies, &String.downcase/1)

      assert Enum.any?(cookies, &String.contains?(&1, "_ashy_walnut_desk_key="))
      refute Enum.any?(cookies_downcased, &String.contains?(&1, "secure"))
    end)
  end

  defp sign_in_with_magic_link(conn, email) do
    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == "/"
    conn
  end

  defp with_session_options(overrides, fun) do
    key = :session_options
    old = Application.fetch_env!(:ashy_walnut_desk, key)

    try do
      Application.put_env(:ashy_walnut_desk, key, Keyword.merge(old, overrides))
      fun.()
    after
      Application.put_env(:ashy_walnut_desk, key, old)
    end
  end
end
