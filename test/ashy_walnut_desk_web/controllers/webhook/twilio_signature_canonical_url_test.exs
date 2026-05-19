defmodule AshyWalnutDeskWeb.Webhook.TwilioSignatureCanonicalUrlTest do
  @moduledoc """
  Sec-fix R3 — when `:twilio_webhook_url` is configured (deployer
  is behind a reverse proxy that may rewrite Host), the signature
  plug verifies against THAT pinned URL — not the conn-derived URL.

  This protects against:
  - Legit Twilio requests being 403-rejected when a proxy rewrites
    Host between Twilio and our app.
  - An attacker mucking with `Host:` to flip the canonical string
    that goes into HMAC (still can't forge a signature without the
    auth token, but removing one attacker-controlled input from the
    canonical path is hygiene).
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Adapters.Twilio
  alias AshyWalnutDesk.Interaction.Channel

  @canonical_url "https://desk.example.com/webhook/twilio"
  @auth_token "test-only-twilio-auth-token"
  @form_params %{"MessageSid" => "SMtest", "From" => "+15551239999", "Body" => "hi"}

  setup do
    prev_token = Application.get_env(:ashy_walnut_desk, :twilio_auth_token)
    prev_require = Application.get_env(:ashy_walnut_desk, :twilio_signature_required, false)
    prev_url = Application.get_env(:ashy_walnut_desk, :twilio_webhook_url)

    Application.put_env(:ashy_walnut_desk, :twilio_auth_token, @auth_token)
    Application.put_env(:ashy_walnut_desk, :twilio_signature_required, true)
    Application.put_env(:ashy_walnut_desk, :twilio_webhook_url, @canonical_url)

    on_exit(fn ->
      restore(:twilio_auth_token, prev_token)
      Application.put_env(:ashy_walnut_desk, :twilio_signature_required, prev_require)
      restore(:twilio_webhook_url, prev_url)
    end)

    admin = AccountsFixtures.create_user(:admin)

    {:ok, _channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: Atom.to_string(Twilio)
        },
        action: :register_channel,
        actor: admin
      )

    %{}
  end

  defp restore(key, nil), do: Application.delete_env(:ashy_walnut_desk, key)
  defp restore(key, val), do: Application.put_env(:ashy_walnut_desk, key, val)

  defp sign(url) do
    sorted =
      @form_params
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join(fn {k, v} -> "#{k}#{v}" end)

    :crypto.mac(:hmac, :sha, @auth_token, url <> sorted) |> Base.encode64()
  end

  defp post_with(conn, host, signature) do
    body = Enum.map_join(@form_params, "&", fn {k, v} -> "#{k}=#{URI.encode_www_form(v)}" end)

    # `Plug.Conn` rejects setting "host" as a header — host lives on
    # `conn.host`. Set it directly.
    %{conn | host: host}
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Conn.put_req_header("x-twilio-signature", signature)
    |> post(~p"/webhook/twilio", body)
  end

  test "signature signed against the pinned URL is accepted (200)", %{conn: conn} do
    sig = sign(@canonical_url)
    # Spoof the Host header to something else — verification should
    # still succeed because the plug uses the pinned URL, not Host.
    resp = post_with(conn, "attacker.example.com", sig)
    refute resp.status == 403
  end

  test "signature signed against a different host is rejected (403)", %{conn: conn} do
    sig = sign("https://attacker.example.com/webhook/twilio")
    resp = post_with(conn, "attacker.example.com", sig)
    assert resp.status == 403
  end
end
