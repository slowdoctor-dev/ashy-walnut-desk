defmodule AshyWalnutDeskWeb.Webhook.WebhookBodySizeTest do
  @moduledoc """
  Sec-fix R9 — the webhook pipeline rejects oversized POST bodies
  before parsing. The default Plug.Parsers limit is 8 MB, which is
  excessive for Twilio's payloads (well under 10 KB). The pipeline
  caps at 64 KB; over-limit bodies return 413 Request Entity Too
  Large (or 400) instead of consuming memory parsing them.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  setup do
    case :ets.whereis(:__awd_rate_limit__) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:__awd_rate_limit__)
    end

    :ok
  end

  test "oversized POST body is rejected by the endpoint parser", %{conn: conn} do
    # 250 KB body — over the 200 KB endpoint cap.
    big_body =
      Enum.map_join(1..2_500, "&", fn i ->
        "MessageSid#{i}=#{URI.encode_www_form(String.duplicate("x", 100))}"
      end)

    assert byte_size(big_body) > 200_000

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      conn
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("x-twilio-signature", "anything")
      |> post(~p"/webhook/twilio", big_body)
    end
  end
end
