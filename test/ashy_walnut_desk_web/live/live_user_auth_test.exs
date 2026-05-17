defmodule AshyWalnutDeskWeb.LiveUserAuthTest do
  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink

  defmodule ProbeLive do
    use AshyWalnutDeskWeb, :live_view

    on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}

    @impl true
    def mount(_params, session, socket) do
      if parent = session["parent_pid"] do
        send(
          parent,
          {:probe_mount, connected?(socket),
           socket.assigns.current_user && socket.assigns.current_user.email}
        )
      end

      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div id="probe-user">{(@current_user && @current_user.email) || "none"}</div>
      """
    end
  end

  test "load_from_cookie assigns current_user from a valid cookie session and covers HTTP+WS mounts",
       %{conn: conn} do
    {conn, session_user, email} =
      signed_in_conn_with_user_session(conn, "load-cookie-valid@example.com")

    conn = recycle(conn)

    # `require_token_presence_for_authentication?(true)` (F3) stores
    # the JWT under `"user_token"`. Pass it through to live_isolated
    # in the same shape so the LV's on_mount can decode it.
    {:ok, view, _html} =
      live_isolated(conn, ProbeLive,
        session: %{"parent_pid" => self(), "user_token" => session_user}
      )

    assert_receive {:probe_mount, false, loaded_email_http}
    assert to_string(loaded_email_http) == email

    assert_receive {:probe_mount, true, loaded_email_ws}
    assert to_string(loaded_email_ws) == email

    assert has_element?(view, "#probe-user", email)
  end

  test "load_from_cookie assigns nil when cookie session is missing", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, ProbeLive, session: %{"parent_pid" => self()})

    assert_receive {:probe_mount, false, nil}
    assert_receive {:probe_mount, true, nil}
    assert has_element?(view, "#probe-user", "none")
  end

  test "load_from_cookie assigns nil when cookie token is malformed", %{conn: conn} do
    {:ok, view, _html} =
      live_isolated(conn, ProbeLive,
        session: %{"parent_pid" => self(), "user_token" => "not-a-valid-jwt"}
      )

    assert_receive {:probe_mount, false, nil}
    assert_receive {:probe_mount, true, nil}
    assert has_element?(view, "#probe-user", "none")
  end

  test "magic-link sign-in still reaches authenticated live route with current_user", %{
    conn: conn
  } do
    {conn, _session_user, email} =
      signed_in_conn_with_user_session(conn, "load-cookie-e2e@example.com")

    conn = recycle(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ email
    assert has_element?(view, "a[href='/sign-out']", "Sign out")
  end

  defp signed_in_conn_with_user_session(conn, email) do
    strategy = Info.strategy!(AshyWalnutDesk.Accounts.User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)

    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == "/"

    # With `require_token_presence_for_authentication?(true)` (F3),
    # the session value is stored under `"user_token"`. AshAuthentication
    # used to key on `:user` (subject string). Read both for forward
    # compatibility.
    session_user = get_session(conn, :user_token) || get_session(conn, :user)
    assert is_binary(session_user)

    {conn, session_user, email}
  end
end
