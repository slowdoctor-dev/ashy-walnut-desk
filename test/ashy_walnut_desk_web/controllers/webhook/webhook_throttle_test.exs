defmodule AshyWalnutDeskWeb.Webhook.WebhookThrottleTest do
  @moduledoc """
  Story 3.8 AC1 — the `:webhook` pipeline rate-limits abuse to 60
  req/min per IP. Beyond that, the plug returns `429 rate_limited`
  WITHOUT touching the signature verifier or intake transaction.

  This is independent of the signature gate (story 3.3): rate limit
  absorbs flood; signature rejects forged payloads. Both are
  required.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  setup do
    # Reset the ETS counter table between tests so a prior test's
    # 60-request budget doesn't bleed into this one.
    case :ets.whereis(:__awd_rate_limit__) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:__awd_rate_limit__)
    end

    # Force the signature plug to reject (rather than fall through
    # to the controller) so each "allowed" request short-circuits
    # at the signature gate with 403. This isolates the throttle
    # test from the controller body.
    prev = Application.get_env(:ashy_walnut_desk, :twilio_signature_required, false)
    Application.put_env(:ashy_walnut_desk, :twilio_signature_required, true)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_signature_required, prev) end)

    :ok
  end

  defp webhook_post(conn) do
    # Forged signature is fine for this test — we're testing the
    # throttle which runs BEFORE the signature verifier. The body
    # never makes it to the controller.
    conn
    |> Plug.Conn.put_req_header("x-twilio-signature", "forged")
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(
      ~p"/webhook/twilio",
      "MessageSid=SM-test&From=%2B15551234567&To=%2B15557654321&Body=hi"
    )
  end

  test "first 20 requests succeed-or-403 (within throttle window)", %{conn: conn} do
    # Sec-fix R1: the limit was lowered from 60 to 20 req/min/IP.
    # 20 is comfortably above Twilio's own retry cadence and well
    # below abuse-flood. None of these should 429; they 403 at the
    # signature gate (forged signature).
    for _ <- 1..20 do
      response = webhook_post(conn)
      assert response.status in [200, 403], "got #{response.status}"
      refute response.status == 429
    end
  end

  test "the 21st request gets 429 from the throttle", %{conn: conn} do
    # Burn the budget.
    for _ <- 1..20 do
      _ = webhook_post(conn)
    end

    # 21st request — same IP, same minute.
    over_limit = webhook_post(conn)
    assert over_limit.status == 429
    assert over_limit.resp_body =~ "rate_limited"
  end
end
