defmodule AshyWalnutDeskWeb.Webhook.TwilioSignaturePlug do
  @moduledoc """
  Plug that validates Twilio's `X-Twilio-Signature` against the
  request body keyed on `TWILIO_AUTH_TOKEN`. Halts with 403 on
  rejection.

  Signature spec: HMAC-SHA1 over `URL + sorted-form-fields` (see
  `Adapters.Twilio.verify_inbound_signature/4`).

  See `specs/phase-3/architecture.md §5.2`.
  """

  @behaviour Plug

  import Plug.Conn

  alias AshyWalnutDesk.Interaction.Adapters.Twilio

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.fetch_env(:ashy_walnut_desk, :twilio_auth_token) do
      {:ok, secret} when is_binary(secret) and secret != "" ->
        verify_or_reject(conn, secret)

      _ ->
        # No secret configured → dev/test bypass mode. Production
        # boots fail in `config/runtime.exs` if the env var is
        # missing (story 3.5 wires that). This branch is the
        # explicit dev/test fixture path.
        if Application.get_env(:ashy_walnut_desk, :twilio_signature_required, false) do
          reject(conn, :missing_secret)
        else
          conn
        end
    end
  end

  defp verify_or_reject(conn, secret) do
    signature = signature_header(conn)
    full_url = full_url(conn)

    case Twilio.verify_inbound_signature(full_url, conn.body_params, signature, secret) do
      :ok -> conn
      {:error, reason} -> reject(conn, reason)
    end
  end

  defp signature_header(conn) do
    case get_req_header(conn, "x-twilio-signature") do
      [s | _] -> s
      _ -> ""
    end
  end

  # Sec-fix R3: prefer the deployer-configured canonical webhook URL
  # over reconstructing from `conn.host`. `conn.host` mirrors the
  # `Host:` request header (or whatever the reverse proxy forwards),
  # which:
  # 1. Breaks signature verification when a reverse proxy rewrites
  #    Host (Twilio computed the sig over the URL it posted to;
  #    behind a proxy we may see a different hostname).
  # 2. Removes one input under attacker control from the signature
  #    canonical string. Even though an attacker can't forge a valid
  #    signature without `TWILIO_AUTH_TOKEN`, reducing trust on
  #    request-shaped inputs in the verification path is hygiene.
  #
  # Deployers set `TWILIO_WEBHOOK_URL` (e.g.
  # "https://desk.example.com/webhook/twilio"). If unset, falls
  # back to the conn-derived URL — preserving the current behavior
  # for tests and the dev mode that bypasses verification anyway.
  defp full_url(conn) do
    case Application.get_env(:ashy_walnut_desk, :twilio_webhook_url) do
      url when is_binary(url) and url != "" -> url
      _ -> conn_derived_url(conn)
    end
  end

  defp conn_derived_url(conn) do
    scheme = Atom.to_string(conn.scheme)
    host = conn.host

    port =
      case {scheme, conn.port} do
        {"http", 80} -> ""
        {"https", 443} -> ""
        {_, p} -> ":#{p}"
      end

    "#{scheme}://#{host}#{port}#{conn.request_path}"
  end

  defp reject(conn, reason) do
    require Logger
    Logger.warning("twilio webhook signature rejected: #{inspect(reason)}")

    conn
    |> send_resp(403, "invalid signature")
    |> halt()
  end
end
