defmodule AshyWalnutDesk.Interaction.Jobs.OutboundSendTest do
  @moduledoc """
  Story 3.5 AC2 — the Oban worker runs the Twilio send path with a
  stable `Idempotency-Key` header derived from
  `Action.outbound_idempotency_key`. Re-running the job (Oban retry,
  worker crash recovery) sends the same key on every attempt so
  Twilio dedupes server-side.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{Inbox, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  setup do
    # Track outbound HTTP attempts so the test can assert idempotency
    # header stability across retries. The plug captures into the
    # process dictionary because it runs in the same process as the
    # worker (Oban drain_queue + Req under :manual mode).
    Process.put(:twilio_attempts, [])

    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])

    capture_plug = fn conn ->
      headers = Map.new(conn.req_headers)
      attempt = %{idempotency_key: headers["idempotency-key"]}
      Process.put(:twilio_attempts, [attempt | Process.get(:twilio_attempts, [])])

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{"sid" => "SMxx-success", "status" => "queued", "to" => "+15551234567"})
      )
    end

    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: capture_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)

    %{}
  end

  defp attempts, do: Process.get(:twilio_attempts, []) |> Enum.reverse()

  defp twilio_chain do
    Fixtures.seed_approved_chain(
      adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio",
      slug: "twilio-sms-#{System.unique_integer([:positive])}"
    )
  end

  test "worker executes Twilio path and writes outbound Message + Inbox transition" do
    %{operator: operator, draft: draft, inbox: inbox, action: action} = twilio_chain()
    Fixtures.backdate_approval!(draft, 6)

    executed = Fixtures.execute_action!(action, operator)

    assert executed.status == :executed
    refute is_nil(executed.executed_at)
    assert executed.adapter_response["provider_message_id"] == "SMxx-success"

    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read_one!()

    assert outbound.approved_by_id == draft.approved_by_id
    assert outbound.outbound_idempotency_key == action.outbound_idempotency_key

    {:ok, reloaded_inbox} = Ash.get(Inbox, inbox.id, actor: operator)
    assert reloaded_inbox.status == :executed
  end

  test "Idempotency-Key header equals Action.outbound_idempotency_key" do
    %{operator: operator, draft: draft, action: action} = twilio_chain()
    Fixtures.backdate_approval!(draft, 6)

    _executed = Fixtures.execute_action!(action, operator)

    assert [%{idempotency_key: key}] = attempts()
    assert is_binary(key)
    assert key == action.outbound_idempotency_key
    assert String.starts_with?(key, "action-")
  end
end
