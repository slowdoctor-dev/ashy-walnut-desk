defmodule AshyWalnutDeskWeb.Router do
  use AshyWalnutDeskWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  # F6: CSP for prod browsers. Dev / test serve CSP-less because:
  # - Phoenix LiveReloader + LiveDashboard inject inline scripts +
  #   iframes that violate `script-src 'self'` / `frame-ancestors
  #   'none'` (silently — Chromium aborts the WS handshake with
  #   "WebSocket is closed before connection established", which is
  #   indistinguishable from a server-side close).
  # - Playwright/headless Chromium honors CSP strictly. Screenshot
  #   capture (`just phase2-screenshots`) needs WS / longpoll to
  #   reach the server, which a `default-src 'self'` baseline
  #   ironically blocks in some Chromium versions.
  # Prod keeps the strict CSP; the deployer's prod env runs without
  # LiveReloader / LiveDashboard so the inline-script problem is
  # moot. See `secure_browser_headers/0` below.
  @secure_browser_headers AshyWalnutDeskWeb.SecurityHeaders.browser_headers()

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AshyWalnutDeskWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  # F2/A2: per-IP throttle for unauthenticated, abuse-prone auth
  # routes (magic-link request + confirm). Conservative defaults:
  # 10 requests per minute. Tune at deployer scale.
  pipeline :auth_throttled do
    plug AshyWalnutDeskWeb.Plugs.RateLimit,
      scope: :auth,
      max_requests: 10,
      window_ms: 60_000
  end

  # Phase 3 / story 3.3: public webhook endpoint. No browser
  # session, no CSRF (Twilio doesn't carry a CSRF token);
  # signature verification is the auth boundary.
  # Per-IP rate limit + signature verification are independent
  # protections; the rate limit absorbs flood/abuse while the
  # signature gate rejects forged payloads.
  pipeline :webhook do
    plug :accepts, ["html", "json"]
    # The endpoint-level `Plug.Parsers` (200 KB cap, sec-fix R9)
    # has already parsed the body by the time we reach this
    # pipeline, so this declaration is redundant but kept for
    # documentation: the webhook accepts urlencoded + json.
    plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason

    # Sec-fix R1: lowered from 60→20 req/min. Twilio's own retry
    # policy is exponential backoff (3–5 retries over ~30 min on
    # 5xx), so 20/min is comfortably above legitimate traffic per
    # number. The wider limit was a flood-absorption knob; deployers
    # with high-volume A2P 10DLC campaigns can raise it explicitly.
    plug AshyWalnutDeskWeb.Plugs.RateLimit,
      scope: :webhook,
      max_requests: 20,
      window_ms: 60_000
  end

  scope "/", AshyWalnutDeskWeb do
    pipe_through :browser

    live_session :authenticated_routes,
      on_mount: [{AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}] do
      live "/", WelcomeLive

      live "/identities", IdentityLive.Index, :index
      live "/identities/new", IdentityLive.New, :new
      live "/identities/:id", IdentityLive.Show, :show
      live "/identities/:id/edit", IdentityLive.Edit, :edit
      live "/inbox", InboxLive.Index, :index
      live "/inbox/new", InboxLive.New, :new
      live "/inbox/:id", InboxLive.Show, :show

      # Story 3.7: admin-only audit-chain viewer (resolves TO-14).
      # `AuditLive.Chain` additionally enforces `:admin_required` on
      # its own `on_mount` stack, so non-admin authenticated users
      # are redirected back to `/sign-in`.
      live "/audit/chain", AuditLive.Chain, :index
    end
  end

  scope "/webhook", AshyWalnutDeskWeb.Webhook do
    pipe_through :webhook

    post "/twilio", TwilioController, :receive_inbound
  end

  scope "/", AshyWalnutDeskWeb do
    pipe_through [:browser, :auth_throttled]

    auth_routes AuthController, AshyWalnutDesk.Accounts.User, path: "/auth"
    sign_out_route AuthController

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{AshyWalnutDeskWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    AshyWalnutDeskWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  AshyWalnutDeskWeb.AuthOverrides,
                  Elixir.AshAuthentication.Phoenix.Overrides.Default
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route AshyWalnutDesk.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [
        AshyWalnutDeskWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.Default
      ]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(AshyWalnutDesk.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [
        AshyWalnutDeskWeb.AuthOverrides,
        Elixir.AshAuthentication.Phoenix.Overrides.Default
      ]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", AshyWalnutDeskWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:ashy_walnut_desk, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AshyWalnutDeskWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
