defmodule AshyWalnutDeskWeb.Auth.SessionRevocationTest do
  @moduledoc """
  A3 regression — sign-out must invalidate captured session cookies
  before the JWT naturally expires. The captured-cookie replay
  scenario covers exfiltration via XSS, malware, or a lost
  device — clicking "Sign out" must take effect server-side.

  Pinned by `require_token_presence_for_authentication?(true)` in
  `Accounts.User.tokens` block (F3). Without that flag, the JWT
  signature is verified standalone and the revocation row written
  by `clear_session/2` isn't consulted, so a captured cookie
  remains valid until the JWT's natural expiry (default 14 days).
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink

  @session_cookie_name "_ashy_walnut_desk_key"

  test "captured session cookie cannot replay after sign-out", %{conn: conn} do
    email = "session-revocation-#{System.unique_integer([:positive])}@example.com"

    # 1. Sign in via magic link. Conn gets a session cookie.
    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    signed_in_conn =
      conn
      |> post(~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

    assert redirected_to(signed_in_conn) == "/"

    captured_cookie = fetch_session_cookie!(signed_in_conn)
    refute captured_cookie == nil

    # 2. Sanity check: a fresh conn carrying the captured cookie
    # successfully reaches the authenticated welcome page.
    replay_before =
      build_conn()
      |> put_req_cookie(@session_cookie_name, captured_cookie)
      |> get(~p"/")

    assert html_response(replay_before, 200) =~ "Signed in as"

    # 3. Sign out via the same conn (the cookie holder). The
    # sign-out endpoint is a DELETE on `/sign-out` (the GET path
    # only renders a confirmation LV).
    sign_out_conn =
      build_conn()
      |> put_req_cookie(@session_cookie_name, captured_cookie)
      |> delete(~p"/sign-out")

    # Sign-out redirects after revoking the session token.
    assert sign_out_conn.status in [200, 302]

    # 4. Replay the captured cookie on a fresh conn. With F3 in
    # place, the cookie is rejected server-side because its
    # token row was revoked on sign-out. Reach /welcome should
    # redirect to /sign-in.
    replay_after =
      build_conn()
      |> put_req_cookie(@session_cookie_name, captured_cookie)
      |> get(~p"/")

    # The LiveView mount halts with a redirect to /sign-in when
    # `current_user` can't be loaded. A non-LV controller would
    # render the public welcome page instead — also acceptable
    # (no auth content leaked). Either way, the page must NOT
    # show "Signed in as" for the captured email.
    body =
      case replay_after.status do
        302 -> ""
        _ -> response(replay_after, 200)
      end

    refute body =~ email,
           "captured session cookie still authenticates after sign-out — " <>
             "session revocation is not enforced (F3 regression)"

    refute body =~ "Signed in as",
           "captured session cookie still resolves a current_user after sign-out — " <>
             "require_token_presence_for_authentication? appears off"
  end

  defp fetch_session_cookie!(conn) do
    case conn.resp_cookies do
      %{@session_cookie_name => %{value: value}} when is_binary(value) and value != "" ->
        value

      _ ->
        # Already-set session cookie from a previous request — pull
        # from the request cookies fall-through.
        Map.get(conn.cookies, @session_cookie_name)
    end
  end
end
