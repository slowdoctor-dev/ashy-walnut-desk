defmodule AshyWalnutDesk.Interaction.Adapters.Twilio do
  @moduledoc """
  Phase 3's real-channel adapter for SMS via Twilio.

  Story 3.2 lands the adapter shell: the behavior conformance for
  the four callbacks (channel_slug, send_outbound,
  verify_inbound_signature, parse_inbound). `verify_inbound_signature`
  and `parse_inbound` are real implementations — the signature
  algorithm is HMAC-SHA1 over `URL + sorted-form-fields` keyed on
  `AUTH_TOKEN`, and `parse_inbound` lifts Twilio's form payload
  into the canonical `InboundMessage` struct.

  `send_outbound/2` returns a *stub-shaped success* in this story
  so the conformance suite can drive the contract end-to-end
  without hitting the network. **Story 3.5** replaces the body
  with the real `Req.post` call to
  `https://api.twilio.com/2010-04-01/Accounts/{SID}/Messages.json`
  per architecture §5.1.

  See ADR-022 and `specs/phase-3/architecture.md §5.1, §5.2`.
  """

  @behaviour AshyWalnutDesk.Interaction.Adapter

  alias AshyWalnutDesk.Interaction.InboundMessage

  @impl true
  def channel_slug, do: "twilio-sms"

  @impl true
  def send_outbound(message, _channel) do
    # Story 3.2: contract-shape only. Story 3.5 swaps in the real
    # Req.post to Twilio's Messages endpoint with Basic auth +
    # Idempotency-Key header.
    {:ok,
     %{
       provider: :twilio,
       provider_message_id: "SM#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}",
       status: "queued",
       to: message.body && "[scrubbed]",
       simulated: true
     }}
  end

  @impl true
  def verify_inbound_signature(full_url, params, signature, secret)
      when is_binary(full_url) and is_map(params) and is_binary(signature) and is_binary(secret) do
    # Twilio signature spec: HMAC-SHA1 of the full URL concatenated
    # with each form-encoded key + value in sorted order, keyed on
    # the AUTH_TOKEN. Result is Base64.
    # https://www.twilio.com/docs/usage/webhooks/webhooks-security
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

  defp parse_received_at(%{"DateSent" => iso}) when is_binary(iso) do
    # Twilio's DateSent is RFC 2822 in their REST responses, but
    # webhook payloads typically don't include it; fall back to
    # server clock for inbound webhooks.
    DateTime.utc_now()
    |> tap(fn _ -> _ = iso end)
  end

  defp parse_received_at(_), do: DateTime.utc_now()
end
