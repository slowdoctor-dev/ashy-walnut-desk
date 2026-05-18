defmodule AshyWalnutDeskWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.

  Implements `:load_from_cookie` per ADR-020 — loads `current_user`
  from the LiveView session map by delegating to
  `AshAuthentication.Plug.Helpers.authenticate_resource_from_session/4`,
  which correctly handles both `:jti` and `:unsafe` session identifier
  modes via the library's own `split_identifier/2`. Avoids the upstream
  `LiveSession.generate_session/3` jti-stripping bug (resolved trade-off
  TO-1 in `specs/security/known-trade-offs.md`).
  """

  import Phoenix.Component
  use AshyWalnutDeskWeb, :verified_routes

  alias AshAuthentication.Plug.Helpers, as: AshAuthHelpers
  alias AshyWalnutDesk.Accounts.User

  @doc """
  Loads `current_user` from the cookie session. Use as the first
  `on_mount` in any LiveView pipeline that needs the user.

      live "/", WelcomeLive,
        on_mount: {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  """
  def on_mount(:load_from_cookie, _params, session, socket) do
    {:cont, assign(socket, :current_user, load_user(session))}
  end

  def on_mount(:current_user, _params, session, socket) do
    {:cont, assign(socket, :current_user, load_user(session))}
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    {:cont, assign_new(socket, :current_user, fn -> load_user(session) end)}
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_new(socket, :current_user, fn -> load_user(session) end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_new(socket, :current_user, fn -> load_user(session) end)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  # Story 3.7: gates admin-only LV routes (e.g. `AuditLive.Chain`).
  # Sends non-admin or unauthenticated users to the sign-in page.
  # Composes with `:load_from_cookie` upstream — assumes
  # `current_user` is already assigned.
  def on_mount(:admin_required, _params, session, socket) do
    socket = assign_new(socket, :current_user, fn -> load_user(session) end)

    case socket.assigns.current_user do
      %User{role: :admin} -> {:cont, socket}
      _ -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}
    end
  end

  defp load_user(session) when is_map(session) do
    case AshAuthHelpers.authenticate_resource_from_session(
           User,
           session,
           :ashy_walnut_desk,
           []
         ) do
      {:ok, %User{} = user} -> user
      _ -> nil
    end
  end

  defp load_user(_), do: nil
end
