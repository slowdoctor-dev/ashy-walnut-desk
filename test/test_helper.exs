ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AshyWalnutDesk.Repo, :manual)

# Story 3.5 / ADR-022: the Twilio adapter hits the network via `Req`.
# Test runs would otherwise reach `api.twilio.com`. Install a default
# stub plug as an anonymous function (process-independent, unlike
# `Req.Test`'s per-process stub registry). Individual tests can swap
# the plug at test time by re-`put_env`-ing
# `:ashy_walnut_desk, :twilio_req_options` for their `describe` /
# `setup` block.
default_twilio_stub = fn conn ->
  conn
  |> Plug.Conn.put_resp_content_type("application/json")
  |> Plug.Conn.send_resp(
    201,
    Jason.encode!(%{
      "sid" => "SM" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower),
      "status" => "queued",
      "to" => "+15551234567"
    })
  )
end

Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: default_twilio_stub)
