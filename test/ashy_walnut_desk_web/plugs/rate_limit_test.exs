defmodule AshyWalnutDeskWeb.Plugs.RateLimitTest do
  @moduledoc """
  F2/A2 regression — per-IP throttle on the auth scope. Conservative
  default of 10 requests per 60s; 11th request from the same client
  gets 429.

  The plug runs on every route in the auth scope (request endpoint
  + confirm endpoint + sign-in form, etc.). The exact route used
  in the test is the GET sign-in page, since it doesn't require
  any setup and the rate-limit semantics are route-agnostic
  (per-IP, per-scope).
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  alias AshyWalnutDeskWeb.Plugs.RateLimit

  setup do
    # Reset the shared ETS table so test runs are independent.
    RateLimit.start_table()
    :ets.delete_all_objects(:__awd_rate_limit__)
    :ok
  end

  test "rejects the 11th request inside the window", %{conn: conn} do
    # Drive 10 hits through the auth-throttled scope; all succeed.
    Enum.each(1..10, fn _ ->
      response = get(conn, ~p"/sign-in")
      assert response.status in 200..399
    end)

    # 11th request from the same client IP gets 429 + retry-after.
    response = get(conn, ~p"/sign-in")
    assert response.status == 429
    assert response.resp_body == "rate_limited"
    assert Plug.Conn.get_resp_header(response, "retry-after") == ["60"]
  end

  test "OPTIONS pre-flight bypasses the limit (plug-level)" do
    opts = RateLimit.init(scope: :test_options, max_requests: 1, window_ms: 60_000)

    # 20 OPTIONS requests, all should pass through with max_requests=1.
    Enum.each(1..20, fn _ ->
      conn = %Plug.Conn{method: "OPTIONS", remote_ip: {127, 0, 0, 1}, req_headers: []}
      refute RateLimit.call(conn, opts).halted
    end)
  end
end
