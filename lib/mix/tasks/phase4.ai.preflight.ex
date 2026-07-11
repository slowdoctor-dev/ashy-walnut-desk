defmodule Mix.Tasks.Phase4.Ai.Preflight do
  @shortdoc "Validate AI runtime config + Anthropic reachability for Phase 4"

  @moduledoc """
  Story 4.8 — Phase 4 entry gate. Fails fast (non-zero exit) when the
  AI draft-generation subsystem would refuse to function at request
  time:

  - `ANTHROPIC_API_KEY` must be present (env var, or
    `config :ashy_walnut_desk, :anthropic, api_key: …` as set by
    `config/runtime.exs` in prod).
  - The configured `:default_model` must be a member of
    `:ai_model_allowlist`.
  - The configured `:ai_adapter` must be a member of
    `:ai_adapter_allowlist`.
  - Active Persona rows with a `model_override` must still be inside
    `:ai_model_allowlist` (catches allowlist drift after rows were
    created — row-level validation only runs at create/update).
  - Unless `--skip-network` is passed, a single low-token health-check
    request goes to Anthropic through `AI.Adapters.Anthropic` to prove
    the key is live. Offline/CI preflight passes `--skip-network`.

  Run before a deployer pushes a Phase 4 release. Mirrors
  `phase3.webhook.preflight`.

  Refs: `specs/phase-4/architecture.md §2` (tooling), ADR-025,
  `specs/phase-4/stories/story-4.8.md` AC1.
  """

  use Mix.Task

  alias AshyWalnutDesk.AI.Adapters.Anthropic
  alias AshyWalnutDesk.AI.Prompt
  alias AshyWalnutDesk.Knowledge.Persona

  require Ash.Query

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [skip_network: :boolean])

    Mix.Task.run("app.start")

    config_failures =
      check_api_key() ++
        check_default_model() ++
        check_adapter_allowlist() ++
        check_persona_overrides()

    {network_failures, network_note} = check_network(opts, config_failures)

    case config_failures ++ network_failures do
      [] ->
        Mix.shell().info("✓ phase4.ai.preflight ok #{network_note}")
        :ok

      failures ->
        Enum.each(failures, fn msg -> Mix.shell().error(msg) end)
        Mix.raise("phase4.ai.preflight: #{length(failures)} check(s) failed")
    end
  end

  defp check_api_key do
    if present?(api_key()) do
      []
    else
      [
        "✗ missing ANTHROPIC_API_KEY — set the env var (prod boot reads it " <>
          "in config/runtime.exs) or config :ashy_walnut_desk, :anthropic, api_key: …"
      ]
    end
  end

  defp check_default_model do
    default = Application.get_env(:ashy_walnut_desk, :default_model)
    allowlist = model_allowlist()

    cond do
      !present?(default) ->
        ["✗ :default_model is not configured"]

      default not in allowlist ->
        [
          "✗ :default_model #{inspect(default)} is not in :ai_model_allowlist " <>
            inspect(allowlist)
        ]

      true ->
        []
    end
  end

  defp check_adapter_allowlist do
    adapter = Application.get_env(:ashy_walnut_desk, :ai_adapter)
    allowlist = Application.get_env(:ashy_walnut_desk, :ai_adapter_allowlist, [])

    cond do
      is_nil(adapter) ->
        ["✗ :ai_adapter is not configured"]

      adapter not in allowlist ->
        [
          "✗ :ai_adapter #{inspect(adapter)} is not in :ai_adapter_allowlist " <>
            inspect(allowlist)
        ]

      true ->
        []
    end
  end

  # Persona.:create/:update validate `model_override` against the
  # allowlist at write time, but a later allowlist change leaves stale
  # rows behind — those would fail at generation time. Surface them here.
  defp check_persona_overrides do
    allowlist = model_allowlist()

    Persona
    |> Ash.Query.filter(not is_nil(model_override))
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, personas} ->
        personas
        |> Enum.reject(fn persona -> persona.model_override in allowlist end)
        |> Enum.map(fn persona ->
          "✗ Persona #{inspect(persona.slug)} has model_override " <>
            "#{inspect(persona.model_override)} outside :ai_model_allowlist #{inspect(allowlist)}"
        end)

      {:error, reason} ->
        ["✗ Persona lookup failed: #{inspect(reason)}"]
    end
  end

  defp check_network(opts, config_failures) do
    cond do
      opts[:skip_network] ->
        {[], "(network check skipped)"}

      config_failures != [] ->
        {[], "(network check not attempted — fix config failures first)"}

      true ->
        run_health_check()
    end
  end

  defp run_health_check do
    prompt = %Prompt{
      model: Application.get_env(:ashy_walnut_desk, :default_model),
      max_tokens: 1,
      system_blocks: [],
      messages: [%{role: "user", content: "preflight health check; reply with one character"}],
      metadata: %{}
    }

    case Anthropic.complete(prompt, receive_timeout: 15_000) do
      {:ok, _response} ->
        {[], "(Anthropic reachable)"}

      {:error, reason} ->
        {["✗ Anthropic health check failed: #{describe_health_failure(reason)}"], ""}
    end
  end

  defp describe_health_failure(:permanent),
    do: "permanent provider rejection — verify ANTHROPIC_API_KEY validity/permissions"

  defp describe_health_failure(:rate_limited),
    do: "rate limited — key is live but throttled; retry shortly"

  defp describe_health_failure(:timeout),
    do: "request timed out — check egress connectivity to api.anthropic.com"

  defp describe_health_failure(:transient),
    do: "transient provider/transport error — retry; check egress connectivity"

  defp describe_health_failure(:content_blocked),
    do: "provider blocked the health-check request — inspect provider-side policy"

  defp describe_health_failure({:model_not_allowed, model}),
    do: "model #{inspect(model)} rejected by the adapter allowlist"

  defp describe_health_failure(other), do: inspect(other)

  defp api_key do
    :ashy_walnut_desk
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(:api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end

  defp model_allowlist do
    Application.get_env(:ashy_walnut_desk, :ai_model_allowlist, [])
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
