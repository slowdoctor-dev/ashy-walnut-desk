defmodule AshyWalnutDesk.AI.Jobs.GenerationWorker do
  @moduledoc false

  use Oban.Worker, queue: :ai_generation, max_attempts: 3

  require Ash.Query
  require Logger

  import Ash.Expr

  alias AshyWalnutDesk.AI.PromptAssembler
  alias AshyWalnutDesk.Interaction.{Draft, Message}
  alias AshyWalnutDesk.Safety.Validators.Composite

  @pubsub AshyWalnutDesk.PubSub

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) when attempt > 0 do
    round(:math.pow(2, attempt - 1) * 30)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"draft_id" => draft_id}}) do
    with {:ok, draft} <- load_draft(draft_id),
         :ok <- ensure_generating(draft),
         {:ok, prompt, model} <- build_prompt(draft),
         {:ok, response} <- run_adapter(prompt, model, draft.id, draft.persona_id),
         validator <- run_validator(response.text, draft.id, model, draft.persona_id),
         :ok <- persist_success(draft, prompt, response, validator) do
      broadcast(draft.id, :generation_complete)
      :ok
    else
      :already_done ->
        :ok

      {:error, :not_found} ->
        Logger.warning("GenerationWorker: draft #{draft_id} not found; treating as success")
        :ok

      {:error, :transient} ->
        raise "generation transient failure"

      {:error, :rate_limited} ->
        raise "generation rate limited"

      {:error, :timeout} ->
        raise "generation timeout"

      {:error, :permanent} ->
        terminal_fail(draft_id, "provider_permanent")

      {:error, :content_blocked} ->
        terminal_fail(draft_id, "provider_blocked")

      {:error, :validator_failed, validator_output} ->
        terminal_fail(draft_id, "validator_failed", validator_output)

      {:error, reason} ->
        Logger.warning("GenerationWorker: unexpected error #{inspect(reason)}")
        raise "generation unexpected failure"
    end
  end

  def perform(%Oban.Job{args: args}) do
    arg_keys = if is_map(args), do: Map.keys(args), else: []
    Logger.error("GenerationWorker: unrecognized job args keys=#{inspect(arg_keys)}")
    {:error, :unrecognized_job_args}
  end

  defp load_draft(draft_id) do
    case Ash.get(Draft, draft_id,
           load: [:persona, inbox: [:conversation]],
           authorize?: false
         ) do
      {:ok, draft} -> {:ok, draft}
      {:error, %Ash.Error.Query.NotFound{}} -> {:error, :not_found}
      {:error, %Ash.Error.Invalid{}} -> {:error, :not_found}
      other -> other
    end
  end

  defp ensure_generating(%Draft{status: :generating}), do: :ok
  defp ensure_generating(%Draft{}), do: :already_done

  defp build_prompt(draft) do
    model = draft.ai_model || default_model()

    persona =
      draft.persona ||
        %{
          id: nil,
          system_prompt: "",
          guardrail_notes: nil,
          model_override: nil,
          disclosure_text: ""
        }

    with {:ok, messages} <- load_messages(draft),
         {:ok, prompt} <-
           PromptAssembler.build(%{
             persona: persona,
             messages: messages,
             model: model,
             metadata: %{draft_id: draft.id, persona_id: draft.persona_id}
           }) do
      {:ok, prompt, model}
    end
  end

  defp load_messages(draft) do
    conversation_id = draft.inbox.conversation_id

    messages =
      Message
      |> Ash.Query.for_read(:read, %{}, authorize?: false)
      |> Ash.Query.filter(expr(conversation_id == ^conversation_id))
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.limit(20)
      |> Ash.read!(authorize?: false)
      |> Enum.reverse()
      |> Enum.map(fn message ->
        %{direction: message.direction, body: message.body, inserted_at: message.created_at}
      end)

    {:ok, messages}
  end

  defp run_adapter(prompt, model, draft_id, persona_id) do
    metadata = %{draft_id: draft_id, model: model, persona_id: persona_id}
    start = System.monotonic_time()
    :telemetry.execute([:awd, :ai, :generation, :start], %{}, metadata)

    result = resolve_adapter().complete(prompt, model: model)

    duration = System.monotonic_time() - start

    case result do
      {:ok, response} ->
        usage = normalize_usage(response.usage)

        :telemetry.execute(
          [:awd, :ai, :generation, :stop],
          Map.merge(%{duration: duration}, usage),
          metadata
        )

        {:ok, response}

      {:error, reason} ->
        :telemetry.execute(
          [:awd, :ai, :generation, :exception],
          %{duration: duration},
          Map.put(metadata, :reason, reason)
        )

        {:error, reason}
    end
  end

  defp run_validator(text, draft_id, model, persona_id) do
    start = System.monotonic_time()
    result = Composite.check(text)
    duration = System.monotonic_time() - start

    :telemetry.execute(
      [:awd, :ai, :validator, :stop],
      %{duration: duration},
      %{
        draft_id: draft_id,
        model: model,
        persona_id: persona_id,
        passed?: result.passed?
      }
    )

    result
  end

  defp persist_success(draft, prompt, response, validator) do
    validator_output =
      validator
      |> Map.from_struct()
      |> Map.update!(:violations, fn violations -> Enum.map(violations, &stringify_map_keys/1) end)
      |> Map.put(:input_tokens, usage_field(response.usage, :input_tokens))
      |> Map.put(:output_tokens, usage_field(response.usage, :output_tokens))
      |> Map.put(:cache_read_tokens, usage_field(response.usage, :cache_read_input_tokens))
      |> Map.put(
        :cache_creation_tokens,
        usage_field(response.usage, :cache_creation_input_tokens)
      )
      |> stringify_map_keys()

    attrs = %{
      body: response.text,
      ai_prompt: Jason.encode!(prompt_to_map(prompt)),
      ai_model: draft.ai_model,
      ai_response: response.text,
      ai_validator_output: validator_output
    }

    if validator.passed? do
      case Ash.update(draft, attrs,
             action: :complete_generation,
             authorize?: false,
             context: %{from_generation_worker: true}
           ) do
        {:ok, _} -> :ok
        {:error, %Ash.Error.Invalid{}} -> maybe_idempotent_noop(draft.id)
        other -> other
      end
    else
      {:error, :validator_failed, validator_output}
    end
  end

  defp terminal_fail(draft_id, error_class, validator_output \\ %{}) do
    with {:ok, draft} <- load_draft(draft_id),
         :ok <- ensure_generating(draft),
         output <- terminal_output(error_class, validator_output),
         {:ok, _} <-
           Ash.update(
             draft,
             %{ai_validator_output: output},
             action: :fail_generation,
             authorize?: false,
             context: %{from_generation_worker: true}
           ) do
      broadcast(draft.id, :generation_failed)
      :ok
    else
      :already_done -> :ok
      {:error, :not_found} -> :ok
      {:error, %Ash.Error.Invalid{}} -> maybe_idempotent_noop(draft_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp terminal_output(error_class, validator_output) do
    validator_output
    |> Map.merge(%{"passed?" => false, "error_class" => error_class})
    |> Map.put_new("error_detail_redacted", "[redacted]")
  end

  defp maybe_idempotent_noop(draft_id) do
    with {:ok, draft} <- Ash.get(Draft, draft_id, authorize?: false) do
      if draft.status == :generating, do: {:error, :status_transition_failed}, else: :ok
    end
  end

  defp resolve_adapter do
    module = Application.fetch_env!(:ashy_walnut_desk, :ai_adapter)
    allowlist = Application.get_env(:ashy_walnut_desk, :ai_adapter_allowlist, [])

    if module in allowlist do
      module
    else
      raise "AI adapter not allowed: #{inspect(module)}"
    end
  end

  defp default_model do
    Application.get_env(:ashy_walnut_desk, :default_model, "claude-sonnet-4-6")
  end

  defp prompt_to_map(prompt) do
    %{
      model: prompt.model,
      max_tokens: prompt.max_tokens,
      system_blocks: prompt.system_blocks,
      messages: prompt.messages,
      metadata: prompt.metadata
    }
  end

  defp normalize_usage(usage) do
    %{
      input_tokens: usage_field(usage, :input_tokens),
      output_tokens: usage_field(usage, :output_tokens),
      cache_read_tokens: usage_field(usage, :cache_read_input_tokens),
      cache_creation_tokens: usage_field(usage, :cache_creation_input_tokens)
    }
  end

  defp usage_field(usage, key) do
    usage[key] || usage[to_string(key)] || 0
  end

  defp stringify_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      val = if is_map(value), do: stringify_map_keys(value), else: value
      Map.put(acc, to_string(key), val)
    end)
  end

  defp broadcast(draft_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, "draft:#{draft_id}", event)
  end
end
