defmodule AshyWalnutDeskWeb.Webhook.TwilioController do
  @moduledoc """
  Receives inbound Twilio SMS webhooks. Signature verification is
  in `TwilioSignaturePlug`; this controller takes the verified body,
  parses it via the Twilio adapter into the canonical
  `InboundMessage`, and hands off to `InboundIntake`.

  Idempotency / replay protection (the `InboundDelivery` ledger)
  lands in story 3.4. For now, Twilio retries may double-process —
  acceptable per the story 3.3 deferral.

  See `specs/phase-3/architecture.md §6.2` and ADR-024.
  """

  use AshyWalnutDeskWeb, :controller

  alias AshyWalnutDesk.Interaction.{Adapters, Channel, InboundIntake}

  require Ash.Query

  plug AshyWalnutDeskWeb.Webhook.TwilioSignaturePlug

  @adapter Adapters.Twilio
  @channel_slug "twilio-sms"

  def receive_inbound(conn, params) do
    with {:ok, channel} <- fetch_channel(),
         {:ok, inbound} <- @adapter.parse_inbound(params),
         {:ok, _result} <- InboundIntake.intake(inbound, channel) do
      # Twilio expects a 2xx with TwiML or empty 2xx; empty 200 is
      # the simplest "delivered" response.
      conn
      |> put_resp_content_type("text/xml")
      |> send_resp(200, "<Response></Response>")
    else
      {:error, :missing_required_fields} ->
        conn |> send_resp(400, "bad request") |> halt()

      {:error, :missing_from} ->
        # Audited intake-failure path: invalid payloads still
        # respond 200 so Twilio doesn't retry forever. The failure
        # is logged.
        log_intake_failure(:missing_from, params)

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, "<Response></Response>")

      {:error, :ambiguous_identity_match} ->
        log_intake_failure(:ambiguous_identity_match, params)
        conn |> put_resp_content_type("text/xml") |> send_resp(200, "<Response></Response>")

      {:error, :channel_missing} ->
        conn |> send_resp(503, "channel not registered") |> halt()

      {:error, reason} ->
        log_intake_failure(reason, params)
        conn |> send_resp(500, "intake failed") |> halt()
    end
  end

  defp fetch_channel do
    Channel
    |> Ash.Query.filter(slug == ^@channel_slug)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %Channel{} = channel} -> {:ok, channel}
      {:ok, nil} -> {:error, :channel_missing}
      {:error, _} -> {:error, :channel_lookup_failed}
    end
  end

  defp log_intake_failure(reason, params) do
    require Logger

    Logger.warning(
      "twilio inbound intake failed: #{inspect(reason)} " <>
        "message_sid=#{inspect(params["MessageSid"])}"
    )
  end
end
