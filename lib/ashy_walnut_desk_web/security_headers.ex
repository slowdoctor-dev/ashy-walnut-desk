defmodule AshyWalnutDeskWeb.SecurityHeaders do
  @moduledoc """
  Browser security header configuration. Split out so dev/test can
  ship a CSP-less baseline while prod keeps the strict CSP from F6
  (Phase 2 security review).

  Why the split:

  - Phoenix `LiveReloader` (dev-only) and `LiveDashboard`
    (dev-only `/dev/dashboard`) inject inline scripts + iframes
    that violate `script-src 'self'` and `frame-ancestors 'none'`.
    Chromium silently aborts the LiveView WebSocket handshake
    when CSP rejects a directive that affects the page's transport
    layer (`net::ERR_ABORTED` on `/live/longpoll`,
    `"WebSocket is closed before connection established"` on
    `/live/websocket`).
  - Playwright headless Chromium hits the same problem; screenshot
    capture (`just phase2-screenshots`) needs the LV WS / longpoll
    to fire `phx-click` events, which a strict default-src baseline
    ironically blocks.
  - Prod runs without LiveReloader / LiveDashboard
    (`config.exs` does not set `code_reloader: true`,
    `dev_routes` is unset), so the inline-script problem doesn't
    arise. Strict CSP applies cleanly.

  See the F6 finding in `/tmp/phase2-security-review.md` and the
  screenshot-iteration session that surfaced the dev incompatibility.
  """

  @doc """
  The browser-headers map to pass to
  `Plug.Conn.put_secure_browser_headers/2`. Empty in dev/test
  (Phoenix's defaults still apply: X-Frame-Options, X-Content-Type-
  Options, X-XSS-Protection, etc.). Strict CSP in prod.
  """
  @strict? Application.compile_env(:ashy_walnut_desk, :strict_csp?, false)

  def browser_headers do
    if @strict? do
      %{
        "content-security-policy" =>
          "default-src 'self'; " <>
            "script-src 'self'; " <>
            "style-src 'self' 'unsafe-inline'; " <>
            "img-src 'self' data:; " <>
            "font-src 'self' data:; " <>
            "connect-src 'self' ws: wss:; " <>
            "frame-ancestors 'none'; " <>
            "form-action 'self'; " <>
            "base-uri 'self'"
      }
    else
      %{}
    end
  end
end
