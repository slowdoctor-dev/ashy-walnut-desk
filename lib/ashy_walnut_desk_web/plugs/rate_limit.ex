defmodule AshyWalnutDeskWeb.Plugs.RateLimit do
  @moduledoc """
  Per-IP token-bucket rate limit for unauthenticated abuse-prone
  routes (magic-link request + confirm).

  ETS-backed. Single counter per `{scope, ip}` pair, reset by a
  sliding window of `:window_ms`. On exceed, returns `429 Too Many
  Requests` with a `retry-after` header. Pre-flight `OPTIONS`
  requests bypass the limiter.

  Limits are intentionally conservative defaults (operators-of-one,
  not consumer scale). Tune in deployer's `endpoint.ex` or by
  overriding the plug args in their router.

      plug AshyWalnutDeskWeb.Plugs.RateLimit,
        scope: :magic_link_request,
        max_requests: 10,
        window_ms: 60_000

  See F2 / A2 in the Phase 2 security review.
  """

  @behaviour Plug

  import Plug.Conn

  @table :__awd_rate_limit__

  @doc """
  Starts the ETS table. Idempotent. Called from
  `AshyWalnutDesk.Application.start/2`.
  """
  def start_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        @table
    end
  end

  @impl true
  def init(opts) do
    %{
      scope: Keyword.fetch!(opts, :scope),
      max_requests: Keyword.get(opts, :max_requests, 10),
      window_ms: Keyword.get(opts, :window_ms, 60_000)
    }
  end

  @impl true
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts), do: conn

  def call(conn, %{scope: scope, max_requests: max, window_ms: window}) do
    if exceeded?(conn, scope, max, window) do
      conn
      |> put_resp_header("retry-after", Integer.to_string(div(window, 1_000)))
      |> send_resp(429, "rate_limited")
      |> halt()
    else
      conn
    end
  end

  defp exceeded?(conn, scope, max, window) do
    start_table()
    key = {scope, client_ip(conn)}
    now = System.monotonic_time(:millisecond)
    window_start = now - window

    # Atomic counter increment + read inside a single ETS update.
    # The counter resets when the recorded window_start drifts past
    # the current window.
    case :ets.lookup(@table, key) do
      [{^key, _count, started_at}] when started_at > window_start ->
        new_count = :ets.update_counter(@table, key, {2, 1})
        new_count > max

      _ ->
        :ets.insert(@table, {key, 1, now})
        false
    end
  end

  defp client_ip(conn) do
    # Prefer the X-Forwarded-For first hop when behind a trusted
    # reverse proxy (Cloudflare Tunnel is the documented path —
    # BASELINE §12). If no header is set, fall back to the raw peer
    # IP. The deployer is responsible for stripping forged headers
    # at their edge.
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
