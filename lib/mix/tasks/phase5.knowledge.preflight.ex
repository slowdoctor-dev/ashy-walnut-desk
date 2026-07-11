defmodule Mix.Tasks.Phase5.Knowledge.Preflight do
  @shortdoc "Validate Knowledge/embedding runtime config for Phase 5"

  @moduledoc """
  Story 5.7 — Phase 5 entry gate. Fails fast (non-zero exit) when the
  Knowledge-axis retrieval subsystem would refuse to function at
  request time:

  - The configured `:embedding_adapter` must be in
    `:embedding_adapter_allowlist`. A `nil` adapter is the *valid*
    `EMBEDDING_ADAPTER=none` posture (lexical-only retrieval, ADR-026)
    and passes with a note.
  - `:embedding_dimension` must match the `manual_chunks.embedding`
    column dimension and the configured model's native dimension.
  - When the Voyage adapter is configured, `VOYAGE_API_KEY` (or
    `config :ashy_walnut_desk, :voyage, api_key: …`) must be present.
  - Unless `--skip-network` is passed, one low-cost embed call proves
    the provider is live. Offline/CI preflight passes `--skip-network`.

  Mirrors `phase3.webhook.preflight` / `phase4.ai.preflight`.

  Refs: `specs/phase-5/architecture.md §2` (tooling), ADR-026,
  `specs/phase-5/stories/story-5.7.md` AC1.
  """

  use Mix.Task

  alias AshyWalnutDesk.Knowledge.Embedder
  alias AshyWalnutDesk.Knowledge.Embedders.Voyage
  alias AshyWalnutDesk.Repo

  @model_native_dimensions %{
    "voyage-3.5-lite" => 1024,
    "voyage-3.5" => 1024
  }

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [skip_network: :boolean])

    Mix.Task.run("app.start")

    config_failures = check_adapter() ++ check_dimension() ++ check_provider_key()
    {network_failures, network_note} = check_network(opts, config_failures)

    case config_failures ++ network_failures do
      [] ->
        Mix.shell().info("✓ phase5.knowledge.preflight ok #{network_note}")
        :ok

      failures ->
        Enum.each(failures, fn msg -> Mix.shell().error(msg) end)
        Mix.raise("phase5.knowledge.preflight: #{length(failures)} check(s) failed")
    end
  end

  defp check_adapter do
    case Embedder.resolve() do
      {:ok, _module} ->
        []

      {:error, :not_configured} ->
        # EMBEDDING_ADAPTER=none — supported lexical-only posture.
        []

      {:error, {:embedder_not_allowed, module}} ->
        [
          "✗ :embedding_adapter #{inspect(module)} is not in " <>
            ":embedding_adapter_allowlist " <>
            inspect(Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist, []))
        ]
    end
  end

  defp check_dimension do
    config_dim = Embedder.dimension()
    check_column_dimension(config_dim) ++ check_model_dimension(config_dim)
  end

  defp check_column_dimension(config_dim) do
    case Repo.query(
           "SELECT atttypmod FROM pg_attribute " <>
             "WHERE attrelid = 'manual_chunks'::regclass AND attname = 'embedding'",
           []
         ) do
      {:ok, %{rows: [[column_dim]]}} when column_dim > 0 and column_dim != config_dim ->
        [
          "✗ :embedding_dimension #{config_dim} does not match the " <>
            "manual_chunks.embedding column dimension #{column_dim} — " <>
            "changing dimensions is a migration + full re-embed event"
        ]

      {:ok, _} ->
        []

      {:error, reason} ->
        ["✗ could not inspect manual_chunks.embedding column: #{inspect(reason)}"]
    end
  end

  defp check_model_dimension(config_dim) do
    model = Application.get_env(:ashy_walnut_desk, :embedding_model)

    case Map.get(@model_native_dimensions, model) do
      nil ->
        []

      ^config_dim ->
        []

      native ->
        [
          "✗ model #{inspect(model)} produces #{native}-dimensional vectors " <>
            "but :embedding_dimension is #{config_dim}"
        ]
    end
  end

  defp check_provider_key do
    case Application.get_env(:ashy_walnut_desk, :embedding_adapter) do
      Voyage ->
        if present?(voyage_api_key()) do
          []
        else
          [
            "✗ Voyage embedder configured but VOYAGE_API_KEY is missing — " <>
              "set the env var (prod boot reads it in config/runtime.exs) or " <>
              "config :ashy_walnut_desk, :voyage, api_key: …"
          ]
        end

      _other ->
        []
    end
  end

  defp check_network(opts, config_failures) do
    cond do
      opts[:skip_network] ->
        {[], "(network check skipped)"}

      config_failures != [] ->
        {[], "(network check not attempted — fix config failures first)"}

      match?({:error, :not_configured}, Embedder.resolve()) ->
        {[], "(no external embedder — lexical-only posture, nothing to probe)"}

      true ->
        run_health_check()
    end
  end

  defp run_health_check do
    {:ok, embedder} = Embedder.resolve()

    case embedder.embed(["preflight health check"], input_type: "query") do
      {:ok, [_vector]} ->
        {[], "(embedding provider reachable)"}

      {:error, reason} ->
        {["✗ embedding health check failed: #{describe_health_failure(reason)}"], ""}

      other ->
        {["✗ embedding health check returned unexpected result: #{inspect(other)}"], ""}
    end
  end

  defp describe_health_failure(:permanent),
    do: "permanent provider rejection — verify VOYAGE_API_KEY validity/permissions"

  defp describe_health_failure(:rate_limited),
    do: "rate limited — key is live but throttled; retry shortly"

  defp describe_health_failure(:timeout),
    do: "request timed out — check egress connectivity to the embedding provider"

  defp describe_health_failure(:transient),
    do: "transient provider/transport error — retry; check egress connectivity"

  defp describe_health_failure({:model_not_allowed, model}),
    do: "model #{inspect(model)} rejected by :embedding_model_allowlist"

  defp describe_health_failure(other), do: inspect(other)

  defp voyage_api_key do
    :ashy_walnut_desk
    |> Application.get_env(:voyage, [])
    |> Keyword.get(:api_key) ||
      System.get_env("VOYAGE_API_KEY")
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
