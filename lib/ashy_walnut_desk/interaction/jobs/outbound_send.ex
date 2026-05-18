defmodule AshyWalnutDesk.Interaction.Jobs.OutboundSend do
  @moduledoc """
  Oban worker for outbound channel sends (ADR-023).

  `Action.:execute` enqueues this job after the operator's 5-second
  countdown elapses. The worker loads the chain rows fresh inside its
  own process, resolves the channel adapter, calls
  `Adapter.send_outbound/2`, and drives one of two internal
  transitions on the Action:

  - `{:ok, payload}` → `Action.:complete_outbound` (status `:executed`,
    persists outbound `Message` + Inbox `:mark_executed` +
    `:action_executed` audit event with `outcome: :ok`).
  - `{:error, :transient}` with attempts remaining → return
    `{:error, :transient}` so Oban retries per the schedule below.
  - `{:error, :permanent}` OR transient with attempts exhausted →
    `Action.:fail_outbound` (status `:failed`, error stored,
    `:action_executed` audit event with `outcome: :failed`). Returns
    `:ok` so Oban marks the job complete (the failure is on the
    Action, not the job).

  ## Retry envelope (ADR-023 / §12 Q3)

  5 attempts. Backoff: 30s, 2m, 10m, 30m, 2h. Per-attempt timeout is
  set on the adapter's HTTP client. Total budget ~3h before the
  Action transitions to `:failed` and the operator sees the result in
  `InboxLive.Show` (no auto-retry — re-send means re-approve a new
  Draft for safety).

  The worker thread is the only legitimate caller of
  `Action.:complete_outbound` / `:fail_outbound`; the
  `FromActionWorker` policy check gates them.
  """

  use Oban.Worker,
    queue: :outbound,
    max_attempts: 5,
    unique: [period: 60, keys: [:action_id, :kind]]

  require Logger

  alias AshyWalnutDesk.Interaction.{Action, Channel, Compensation, Draft, Message}

  @transient_backoff [30, 120, 600, 1800, 7200]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) when attempt in 1..5 do
    Enum.at(@transient_backoff, attempt - 1)
  end

  def backoff(%Oban.Job{} = job), do: super(job)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action_id" => action_id, "kind" => "action"} = args} = job) do
    case load_action(action_id) do
      {:ok, action, channel, draft} ->
        run_send(job, action, channel, draft, args)

      {:error, :action_not_found} ->
        Logger.warning(
          "Jobs.OutboundSend: action #{action_id} not found; treating as success (already destroyed)"
        )

        :ok

      {:error, reason} ->
        terminal_fail(action_id, error_text(reason))
    end
  end

  def perform(
        %Oban.Job{args: %{"compensation_id" => compensation_id, "kind" => "compensation"}} = job
      ) do
    case load_compensation(compensation_id) do
      {:ok, compensation, channel, draft} ->
        run_compensation_send(job, compensation, channel, draft)

      {:error, :compensation_not_found} ->
        Logger.warning(
          "Jobs.OutboundSend: compensation #{compensation_id} not found; treating as success"
        )

        :ok

      {:error, reason} ->
        terminal_fail_compensation(compensation_id, error_text(reason))
    end
  end

  # ────────────────────────────────────────────────────────────────
  # Core flow
  # ────────────────────────────────────────────────────────────────

  defp run_send(job, action, channel, draft, args) do
    cond do
      action.status == :executed ->
        # Idempotent re-entry after a worker crash post-DB-commit but
        # pre-Oban-ack. Nothing to do.
        :ok

      action.status in [:failed, :rolled_back] ->
        :ok

      not channel.enabled? ->
        terminal_fail(action.id, "channel disabled")

      true ->
        message = build_outbound_message(action, draft)
        adapter = resolve_adapter!(channel.adapter_module)
        do_attempt(job, action, channel, message, adapter, args)
    end
  end

  defp do_attempt(job, action, channel, message, adapter, _args) do
    case adapter.send_outbound(message, channel) do
      {:ok, payload} ->
        case complete(action, payload) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, error_text(reason)}
        end

      {:error, :transient} ->
        if job.attempt >= job.max_attempts do
          terminal_fail(action.id, "retries exhausted (transient)")
        else
          {:error, :transient}
        end

      {:error, :permanent} ->
        terminal_fail(action.id, "permanent adapter failure")

      {:error, reason} ->
        terminal_fail(action.id, error_text(reason))
    end
  end

  # ────────────────────────────────────────────────────────────────
  # Loading
  # ────────────────────────────────────────────────────────────────

  defp load_action(action_id) do
    with {:ok, action} <- Ash.get(Action, action_id, authorize?: false),
         {:ok, channel} <- Ash.get(Channel, action.channel_id, authorize?: false),
         {:ok, draft} <- Ash.get(Draft, action.draft_id, load: [:inbox], authorize?: false) do
      {:ok, action, channel, draft}
    else
      {:error, %Ash.Error.Invalid{}} -> {:error, :action_not_found}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :action_not_found}
      other -> other
    end
  end

  defp build_outbound_message(action, draft) do
    %Message{
      conversation_id: draft.inbox.conversation_id,
      direction: :outbound,
      body: draft.body,
      approved_by_id: draft.approved_by_id,
      outbound_idempotency_key: action.outbound_idempotency_key
    }
  end

  defp resolve_adapter!(module_name) when is_binary(module_name) do
    Module.concat([module_name])
  end

  # ────────────────────────────────────────────────────────────────
  # Action transitions (worker-only via FromActionWorker)
  # ────────────────────────────────────────────────────────────────

  defp complete(action, payload) do
    Ash.update(
      action,
      %{adapter_response: payload},
      action: :complete_outbound,
      authorize?: false,
      context: %{from_action_worker: true}
    )
  end

  defp terminal_fail(action_id, error_str) do
    with {:ok, action} <- Ash.get(Action, action_id, authorize?: false),
         {:ok, _} <-
           Ash.update(
             action,
             %{error: error_str},
             action: :fail_outbound,
             authorize?: false,
             context: %{from_action_worker: true}
           ) do
      :ok
    else
      {:error, reason} ->
        Logger.error(
          "Jobs.OutboundSend: terminal_fail could not mark Action #{action_id} failed: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)

  # ────────────────────────────────────────────────────────────────
  # Compensation branch (story 3.6)
  # ────────────────────────────────────────────────────────────────

  defp load_compensation(compensation_id) do
    with {:ok, compensation} <- Ash.get(Compensation, compensation_id, authorize?: false),
         {:ok, action} <- Ash.get(Action, compensation.action_id, authorize?: false),
         {:ok, channel} <- Ash.get(Channel, action.channel_id, authorize?: false),
         {:ok, draft} <- Ash.get(Draft, action.draft_id, load: [:inbox], authorize?: false) do
      {:ok, compensation, channel, draft}
    else
      {:error, %Ash.Error.Invalid{}} -> {:error, :compensation_not_found}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :compensation_not_found}
      other -> other
    end
  end

  defp run_compensation_send(job, compensation, channel, draft) do
    cond do
      compensation.status in [:triggered, :failed, :completed] -> :ok
      not channel.enabled? -> terminal_fail_compensation(compensation.id, "channel disabled")
      true -> dispatch_compensation_attempt(job, compensation, channel, draft)
    end
  end

  defp dispatch_compensation_attempt(job, compensation, channel, draft) do
    message = build_compensation_message(compensation, draft)
    adapter = Module.concat([channel.adapter_module])

    adapter.send_outbound(message, channel)
    |> handle_compensation_result(job, compensation, draft)
  end

  defp handle_compensation_result({:ok, payload}, _job, compensation, draft) do
    case complete_compensation(compensation, draft, payload) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, error_text(reason)}
    end
  end

  defp handle_compensation_result({:error, :transient}, job, compensation, _draft) do
    if job.attempt >= job.max_attempts do
      terminal_fail_compensation(compensation.id, "retries exhausted (transient)")
    else
      {:error, :transient}
    end
  end

  defp handle_compensation_result({:error, :permanent}, _job, compensation, _draft) do
    terminal_fail_compensation(compensation.id, "permanent adapter failure")
  end

  defp handle_compensation_result({:error, reason}, _job, compensation, _draft) do
    terminal_fail_compensation(compensation.id, error_text(reason))
  end

  defp build_compensation_message(compensation, draft) do
    %Message{
      conversation_id: draft.inbox.conversation_id,
      direction: :outbound,
      body: compensation.body,
      approved_by_id: draft.approved_by_id,
      outbound_idempotency_key: compensation.outbound_idempotency_key
    }
  end

  defp complete_compensation(compensation, draft, payload) do
    with {:ok, updated} <-
           Ash.update(
             compensation,
             %{adapter_response: payload},
             action: :complete_send,
             authorize?: false,
             context: %{from_action_worker: true}
           ),
         {:ok, _message} <- create_compensation_outbound_message(compensation, draft, updated) do
      {:ok, updated}
    end
  end

  defp create_compensation_outbound_message(compensation, draft, updated_compensation) do
    Ash.create(
      Message,
      %{
        conversation_id: draft.inbox.conversation_id,
        direction: :outbound,
        body: compensation.body,
        sent_at: updated_compensation.triggered_at,
        approved_by_id: draft.approved_by_id,
        outbound_idempotency_key: compensation.outbound_idempotency_key
      },
      action: :record_message,
      authorize?: false,
      context: %{from_action_execute: true}
    )
  end

  defp terminal_fail_compensation(compensation_id, error_str) do
    with {:ok, compensation} <- Ash.get(Compensation, compensation_id, authorize?: false),
         {:ok, _} <-
           Ash.update(
             compensation,
             %{error: error_str},
             action: :fail_send,
             authorize?: false,
             context: %{from_action_worker: true}
           ) do
      :ok
    else
      {:error, reason} ->
        Logger.error(
          "Jobs.OutboundSend: terminal_fail_compensation could not mark Compensation #{compensation_id} failed: #{inspect(reason)}"
        )

        :ok
    end
  end
end
