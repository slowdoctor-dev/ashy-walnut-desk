defmodule AshyWalnutDesk.Interaction.Jobs.OutboundRetryPolicyTest do
  @moduledoc """
  Story 3.5 AC3 — retry policy:

  - Transient adapter failures (HTTP 429 / 5xx / network error) trigger
    Oban retries on the documented backoff schedule until attempts are
    exhausted, then mark the `Action` `:failed` deterministically.
  - Permanent adapter failures (Twilio 4xx with permanent codes) mark
    the `Action` `:failed` immediately with no retries.
  - Backoff `attempt → seconds` matches ADR-023 §12 Q3.
  """

  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Interaction.{Action, Jobs.OutboundSend}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "backoff schedule matches ADR-023 §12 Q3 (30s, 2m, 10m, 30m, 2h)" do
    assert OutboundSend.backoff(%Oban.Job{attempt: 1}) == 30
    assert OutboundSend.backoff(%Oban.Job{attempt: 2}) == 120
    assert OutboundSend.backoff(%Oban.Job{attempt: 3}) == 600
    assert OutboundSend.backoff(%Oban.Job{attempt: 4}) == 1800
    assert OutboundSend.backoff(%Oban.Job{attempt: 5}) == 7200
  end

  test "max_attempts is 5 per ADR-023" do
    config = OutboundSend.__opts__()
    assert Keyword.fetch!(config, :max_attempts) == 5
    assert Keyword.fetch!(config, :queue) == :outbound
  end

  test "transient failure on final attempt marks Action :failed (terminal)" do
    %{operator: operator, draft: draft, action: action} =
      Fixtures.seed_approved_chain(
        adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio",
        slug: "twilio-sms-#{System.unique_integer([:positive])}"
      )

    _ = operator
    Fixtures.backdate_approval!(draft, 6)

    transient_plug = fn conn ->
      Plug.Conn.send_resp(conn, 503, "transient")
    end

    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])
    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: transient_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)

    # Drive the worker directly at attempt 5 (terminal) so we don't
    # have to wait through real Oban backoff in CI.
    perform_job(
      OutboundSend,
      %{"action_id" => action.id, "kind" => "action"},
      attempt: 5,
      max_attempts: 5
    )

    reloaded = Ash.get!(Action, action.id, authorize?: false)
    assert reloaded.status == :failed
    assert reloaded.error =~ "retries exhausted"
  end

  test "transient failure with attempts remaining returns {:error, :transient} (Oban retries)" do
    %{operator: operator, draft: draft, action: action} =
      Fixtures.seed_approved_chain(
        adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio",
        slug: "twilio-sms-#{System.unique_integer([:positive])}"
      )

    Fixtures.backdate_approval!(draft, 6)

    transient_plug = fn conn -> Plug.Conn.send_resp(conn, 429, "rate limited") end
    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])
    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: transient_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)

    {:ok, _scheduled} = Ash.update(action, %{}, action: :execute, actor: operator)

    result =
      perform_job(
        OutboundSend,
        %{"action_id" => action.id, "kind" => "action"},
        attempt: 1,
        max_attempts: 5
      )

    assert result == {:error, :transient}

    # Action stays :scheduled (still in the retry loop); the row
    # transitions to :failed only after the terminal attempt.
    reloaded = Ash.get!(Action, action.id, authorize?: false)
    assert reloaded.status == :scheduled
  end

  test "permanent failure (Twilio 4xx) marks Action :failed without retries" do
    %{operator: operator, draft: draft, action: action} =
      Fixtures.seed_approved_chain(
        adapter_module: "AshyWalnutDesk.Interaction.Adapters.Twilio",
        slug: "twilio-sms-#{System.unique_integer([:positive])}"
      )

    _ = operator
    Fixtures.backdate_approval!(draft, 6)

    permanent_plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(400, Jason.encode!(%{"code" => 21_610, "message" => "unsubscribed"}))
    end

    prev = Application.get_env(:ashy_walnut_desk, :twilio_req_options, [])
    Application.put_env(:ashy_walnut_desk, :twilio_req_options, plug: permanent_plug)
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :twilio_req_options, prev) end)

    # Even on attempt 1, the worker should NOT request retry — it
    # should terminal-fail the Action and return :ok to Oban.
    result =
      perform_job(
        OutboundSend,
        %{"action_id" => action.id, "kind" => "action"},
        attempt: 1,
        max_attempts: 5
      )

    assert result == :ok

    reloaded = Ash.get!(Action, action.id, authorize?: false)
    assert reloaded.status == :failed
    assert reloaded.error =~ "permanent"
  end

  defp perform_job(worker, args, opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 5)

    worker.perform(%Oban.Job{
      args: args,
      attempt: attempt,
      max_attempts: max_attempts
    })
  end
end
