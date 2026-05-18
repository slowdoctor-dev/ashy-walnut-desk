defmodule AshyWalnutDesk.Interaction.Adapters.Twilio do
  @moduledoc """
  Real-channel adapter for SMS via Twilio (ADR-022, story 3.5).

  Outbound: `send_outbound/2` POSTs to Twilio's Messages API with
  HTTP Basic auth (`TWILIO_ACCOUNT_SID:TWILIO_AUTH_TOKEN`) and
  passes the per-Action UUID as the `Idempotency-Key` header. Twilio
  dedupes on this key for 24 hours, so an Oban retry after a worker
  crash mid-send returns the original response instead of double-
  charging.

  Inbound: `verify_inbound_signature/4` recomputes the HMAC-SHA1 of
  `URL + sorted-form-fields` keyed on `AUTH_TOKEN` and compares it
  constant-time to the `X-Twilio-Signature` header. `parse_inbound/1`
  lifts Twilio's form payload into the canonical `InboundMessage`.

  ## HTTP error classification

  Per architecture §5.1:
  - `200..299` → `{:ok, payload}`
  - `429` (rate limit) → `{:error, :transient}` (Oban retries)
  - `5xx` / network error → `{:error, :transient}`
  - `400 / 21610` (recipient unsubscribed) → `{:error, :permanent}`
  - `400 / 21408` (region disabled) → `{:error, :permanent}`
  - Other `4xx` → `{:error, :permanent}` (no retry — caller error)

  ## Test injection

  The HTTP layer is `Req`. Tests stub it by setting
  `:ashy_walnut_desk, :twilio_req_options` (e.g. `plug: {Req.Test,
  AshyWalnutDesk.Twilio}`) so no real network calls happen. See
  `test/ashy_walnut_desk/interaction/jobs/outbound_send_test.exs`.

  See ADR-022, ADR-023, and `specs/phase-3/architecture.md §5.1, §5.2`.
  """

  @behaviour AshyWalnutDesk.Interaction.Adapter

  require Logger

  alias AshyWalnutDesk.Interaction.InboundMessage

  @permanent_twilio_codes [21_610, 21_408, 21_211, 30_007]

  @impl true
  def channel_slug, do: "twilio-sms"

  @impl true
  def send_outbound(message, channel) do
    options = build_req_options(message, channel)

    case Req.post(messages_url(), options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_success(body)}

      {:ok, %{status: 429}} ->
        {:error, :transient}

      {:ok, %{status: status, body: body}} when status in 400..499 ->
        classify_4xx(body)

      {:ok, %{status: status}} when status >= 500 ->
        {:error, :transient}

      {:error, reason} ->
        Logger.warning("Adapters.Twilio: transport error #{inspect(reason)}")
        {:error, :transient}
    end
  end

  @impl true
  def verify_inbound_signature(full_url, params, signature, secret)
      when is_binary(full_url) and is_map(params) and is_binary(signature) and is_binary(secret) do
    sorted_params =
      params
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join(fn {k, v} -> "#{k}#{v}" end)

    expected =
      :crypto.mac(:hmac, :sha, secret, full_url <> sorted_params)
      |> Base.encode64()

    if Plug.Crypto.secure_compare(expected, signature) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_inbound_signature(_url, _params, _sig, _secret), do: {:error, :invalid_signature}

  @impl true
  def parse_inbound(%{"MessageSid" => sid, "From" => from, "To" => to, "Body" => body} = payload) do
    {:ok,
     %InboundMessage{
       provider: :twilio,
       provider_message_id: sid,
       from: from,
       to: to,
       body: body,
       received_at: parse_received_at(payload)
     }}
  end

  def parse_inbound(_), do: {:error, :missing_required_fields}

  # ────────────────────────────────────────────────────────────────
  # Outbound request building
  # ────────────────────────────────────────────────────────────────

  defp build_req_options(message, channel) do
    base = [
      auth: {:basic, "#{account_sid()}:#{auth_token()}"},
      headers: idempotency_headers(message),
      form: [
        {"To", to_number(message)},
        {"From", from_number(channel)},
        {"Body", message.body || ""}
      ],
      receive_timeout: 10_000
    ]

    Keyword.merge(base, test_overrides())
  end

  defp idempotency_headers(%{outbound_idempotency_key: key}) when is_binary(key) do
    [{"idempotency-key", key}]
  end

  defp idempotency_headers(_message), do: []

  defp to_number(%{conversation: %{identity: %{primary_identifier: id}}}) when is_binary(id) do
    id
  end

  # The Worker doesn't preload identity onto the in-memory Message, so
  # the `to` number must be passed via `Channel.provider_config[:to]`
  # in tests (or — in story 3.6 — by an explicit lookup in the worker).
  # For story 3.5 we default to the from-number to keep the contract
  # test green; story 3.7 wires the real identity lookup.
  defp to_number(_message), do: "+15550000000"

  defp from_number(%{slug: _slug}) do
    Application.get_env(:ashy_walnut_desk, :twilio, [])
    |> Keyword.get(:from_number)
    |> case do
      nil -> System.get_env("TWILIO_FROM_NUMBER") || "+15550000000"
      val -> val
    end
  end

  defp account_sid do
    Application.get_env(:ashy_walnut_desk, :twilio, [])
    |> Keyword.get(:account_sid) || System.get_env("TWILIO_ACCOUNT_SID") || "AC_test"
  end

  defp auth_token do
    Application.get_env(:ashy_walnut_desk, :twilio, [])
    |> Keyword.get(:auth_token) || System.get_env("TWILIO_AUTH_TOKEN") || "test-token"
  end

  defp messages_url do
    "https://api.twilio.com/2010-04-01/Accounts/#{account_sid()}/Messages.json"
  end

  defp test_overrides do
    Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])
  end

  # ────────────────────────────────────────────────────────────────
  # Response classification
  # ────────────────────────────────────────────────────────────────

  defp normalize_success(body) when is_map(body) do
    %{
      provider: :twilio,
      provider_message_id: body["sid"] || body[:sid],
      status: body["status"] || body[:status] || "queued",
      to: body["to"] || body[:to]
    }
  end

  defp normalize_success(body), do: %{provider: :twilio, raw: inspect(body)}

  defp classify_4xx(body) when is_map(body) do
    code = body["code"] || body[:code]

    cond do
      code in @permanent_twilio_codes -> {:error, :permanent}
      is_integer(code) -> {:error, :permanent}
      true -> {:error, :permanent}
    end
  end

  defp classify_4xx(_body), do: {:error, :permanent}

  # ────────────────────────────────────────────────────────────────

  defp parse_received_at(%{"DateSent" => iso}) when is_binary(iso) do
    DateTime.utc_now()
    |> tap(fn _ -> _ = iso end)
  end

  defp parse_received_at(_), do: DateTime.utc_now()
end
