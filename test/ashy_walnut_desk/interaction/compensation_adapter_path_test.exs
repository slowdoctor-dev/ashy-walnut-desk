defmodule AshyWalnutDesk.Interaction.CompensationAdapterPathTest do
  @moduledoc """
  Story 3.6 AC3 — compensation invocation uses the same Twilio
  adapter boundary as `Action.:execute`, with its own
  `outbound_idempotency_key` so retries (Oban worker re-runs) dedupe
  at the provider.
  """

  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Interaction.{Compensation, Jobs.OutboundSend, Message}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures
  alias AshyWalnutDesk.Repo

  defp backdate!(compensation, seconds \\ 6) do
    new_ts = DateTime.add(DateTime.utc_now(), -seconds, :second)

    compensation
    |> Ecto.Changeset.change(%{trigger_initiated_at: new_ts})
    |> Repo.update!()
    |> then(&Ash.get!(Compensation, &1.id, authorize?: false))
  end

  defp twilio_chain do
    Fixtures.seed_approved_chain(
      adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio",
      slug: "twilio-sms-#{System.unique_integer([:positive])}"
    )
  end

  setup do
    Process.put(:twilio_attempts, [])

    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])

    capture_plug = fn conn ->
      headers = Map.new(conn.req_headers)
      Process.put(:twilio_attempts, [headers["idempotency-key"] | Process.get(:twilio_attempts)])

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        201,
        Jason.encode!(%{"sid" => "SMxx-comp", "status" => "queued", "to" => "+15551234567"})
      )
    end

    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: capture_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)
    %{}
  end

  defp attempts, do: Process.get(:twilio_attempts, []) |> Enum.reverse()

  test "compensation send uses Twilio adapter with compensation-prefixed Idempotency-Key" do
    %{operator: operator, draft: draft, action: action} = twilio_chain()
    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)
    assert executed.status == :executed

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)
    triggering = backdate!(triggering)
    {:ok, _scheduled} = Ash.update(triggering, %{}, action: :trigger, actor: operator)

    Oban.drain_queue(queue: :outbound, with_recursion: true)

    final = Ash.get!(Compensation, compensation.id, authorize?: false)
    assert final.status == :triggered

    # Two HTTP attempts: action send, then compensation send.
    [action_key, comp_key] = attempts()
    assert is_binary(action_key)
    assert is_binary(comp_key)
    refute action_key == comp_key

    assert String.starts_with?(action_key, "action-")
    assert String.starts_with?(comp_key, "compensation-")
    assert comp_key == final.outbound_idempotency_key
  end

  test "permanent adapter failure marks Compensation :failed without retries" do
    %{operator: operator, draft: draft, action: action} = twilio_chain()
    _ = action
    Fixtures.backdate_approval!(draft, 6)
    executed = Fixtures.execute_action!(action, operator)

    compensation =
      Compensation
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(action_id == ^executed.id))
      |> Ash.read_one!()

    {:ok, triggering} = Ash.update(compensation, %{}, action: :initiate_trigger, actor: operator)
    triggering = backdate!(triggering)
    {:ok, _scheduled} = Ash.update(triggering, %{}, action: :trigger, actor: operator)

    permanent_plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(400, Jason.encode!(%{"code" => 21_610, "message" => "unsub"}))
    end

    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])
    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: permanent_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)

    result =
      OutboundSend.perform(%Oban.Job{
        args: %{"compensation_id" => compensation.id, "kind" => "compensation"},
        attempt: 1,
        max_attempts: 5
      })

    assert result == :ok

    reloaded = Ash.get!(Compensation, compensation.id, authorize?: false)
    assert reloaded.status == :failed
    assert reloaded.error =~ "permanent"

    # No second outbound Message created on failure.
    outbound =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(direction == :outbound))
      |> Ash.read!()

    assert length(outbound) == 1
  end
end
