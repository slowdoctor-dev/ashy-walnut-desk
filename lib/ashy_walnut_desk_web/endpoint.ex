defmodule AshyWalnutDeskWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ashy_walnut_desk

  # Session options live in app env (`config :ashy_walnut_desk,
  # :session_options`) so `runtime.exs` can override `secure` /
  # `http_only` at prod boot keyed on `PHX_HOST` (ADR-021). The
  # socket connect_info must match what `Plug.Session` sees, so we
  # read the same env at compile time — the socket route is
  # rewritten on app boot, and the per-request plug below re-reads
  # at runtime so dev/prod overrides actually win.
  @session_options Application.compile_env!(:ashy_walnut_desk, :session_options)

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :ashy_walnut_desk,
    gzip: false,
    only: AshyWalnutDeskWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :ashy_walnut_desk
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug :put_session_options
  plug AshyWalnutDeskWeb.Router

  # Read session options at request time so `runtime.exs` overrides
  # (e.g. `secure: true` keyed on `PHX_HOST` per ADR-021) actually
  # land on the `Plug.Session` plug. Without this indirection the
  # `@session_options` module attribute would bake in compile-time
  # values and silently ignore runtime config changes.
  defp put_session_options(conn, _opts) do
    opts =
      :ashy_walnut_desk
      |> Application.fetch_env!(:session_options)
      |> Plug.Session.init()

    Plug.Session.call(conn, opts)
  end
end
