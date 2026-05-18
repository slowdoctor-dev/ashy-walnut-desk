defmodule AshyWalnutDeskWeb.Webhook.TwilioSignatureTest do
  @moduledoc """
  Story 3.3 AC1 — Twilio webhook signature verification.
  Valid sig → 200; invalid / missing → 403.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{Adapter, Channel}

  @url "http://www.example.com/webhook/twilio"
  @auth_token "test-only-twilio-auth-token"

  setup do
    original_token = Application.get_env(:ashy_walnut_desk, :twilio_auth_token)
    original_require = Application.get_env(:ashy_walnut_desk, :twilio_signature_required, false)
    Application.put_env(:ashy_walnut_desk, :twilio_auth_token, @auth_token)
    Application.put_env(:ashy_walnut_desk, :twilio_signature_required, true)

    on_exit(fn ->
      if is_nil(original_token) do
        Application.delete_env(:ashy_walnut_desk, :twilio_auth_token)
      else
        Application.put_env(:ashy_walnut_desk, :twilio_auth_token, original_token)
      end

      Application.put_env(:ashy_walnut_desk, :twilio_signature_required, original_require)
    end)

    admin = AccountsFixtures.create_user(:admin)

    {:ok, _channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: Atom.to_string(AshyWalnutDesk.Interaction.Adapters.Twilio)
        },
        action: :register_channel,
        actor: admin
      )

    :ok
  end

  defp twilio_signature(params) do
    sorted =
      params
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join(fn {k, v} -> "#{k}#{v}" end)

    :crypto.mac(:hmac, :sha, @auth_token, @url <> sorted) |> Base.encode64()
  end

  test "valid Twilio signature → 200", %{conn: conn} do
    params = %{
      "MessageSid" => "SM" <> String.duplicate("0", 32),
      "From" => "+15551234567",
      "To" => "+15557654321",
      "Body" => "valid sig"
    }

    sig = twilio_signature(params)

    response =
      conn
      |> put_req_header("x-twilio-signature", sig)
      |> Map.put(:host, "www.example.com")
      |> Map.put(:port, 80)
      |> post(~p"/webhook/twilio", params)

    assert response.status == 200, "expected 200, got #{response.status}: #{response.resp_body}"
  end

  test "missing X-Twilio-Signature → 403", %{conn: conn} do
    params = %{
      "MessageSid" => "SM" <> String.duplicate("1", 32),
      "From" => "+15551234567",
      "To" => "+15557654321",
      "Body" => "missing sig"
    }

    response = post(conn, ~p"/webhook/twilio", params)

    assert response.status == 403
  end

  test "invalid X-Twilio-Signature → 403", %{conn: conn} do
    params = %{
      "MessageSid" => "SM" <> String.duplicate("2", 32),
      "From" => "+15551234567",
      "To" => "+15557654321",
      "Body" => "bad sig"
    }

    response =
      conn
      |> put_req_header("x-twilio-signature", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
      |> post(~p"/webhook/twilio", params)

    assert response.status == 403
  end

  test "Adapter.stub_module_string returns canonical name", _ctx do
    assert Adapter.stub_module_string() ==
             Atom.to_string(AshyWalnutDesk.Interaction.Adapters.Stub)
  end
end
