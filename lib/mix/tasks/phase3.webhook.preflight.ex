defmodule Mix.Tasks.Phase3.Webhook.Preflight do
  @shortdoc "Validate Twilio config + channel bootstrap for Phase 3"

  @moduledoc """
  Story 3.1 — Phase 3 entry gate. Fails fast (non-zero exit) when the
  Twilio integration would refuse to function at request time:

  - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`
    env vars must be present.
  - A `Channel` row with `slug: "twilio-sms"` must be registered (so
    the outbound path has somewhere to resolve to).

  Run before a deployer pushes a Phase 3 release. CI can also gate
  on this to catch a deployment-config regression early. Subsequent
  stories (3.5 outbound, 3.8 integration gate) depend on these
  prerequisites; this task surfaces the failure before any
  webhook traffic or send is attempted.

  Refs: `specs/phase-3/requirements.md` AC #13 (preflight gate),
  `specs/phase-3/architecture.md §9.1`, ADR-022.
  """

  use Mix.Task

  alias AshyWalnutDesk.Interaction.Channel
  require Ash.Query

  @required_env_vars ~w(TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER)
  @channel_slug "twilio-sms"

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    failures = check_env_vars() ++ check_twilio_channel()

    case failures do
      [] ->
        Mix.shell().info("✓ phase3.webhook.preflight ok")
        :ok

      fs ->
        Enum.each(fs, fn msg -> Mix.shell().error(msg) end)
        Mix.raise("phase3.webhook.preflight: #{length(fs)} check(s) failed")
    end
  end

  defp check_env_vars do
    @required_env_vars
    |> Enum.reject(fn var -> present?(System.get_env(var)) end)
    |> Enum.map(fn var -> "✗ missing env var: #{var}" end)
  end

  defp check_twilio_channel do
    Channel
    |> Ash.Query.filter(slug == @channel_slug)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        [
          "✗ Channel{slug: \"#{@channel_slug}\"} is not registered — " <>
            "create one via Ash.create(Channel, …, action: :register_channel)"
        ]

      {:ok, %Channel{enabled?: false}} ->
        [
          "✗ Channel{slug: \"#{@channel_slug}\"} exists but is disabled — " <>
            "re-enable via Ash.update(channel, %{}, action: :enable)"
        ]

      {:ok, %Channel{}} ->
        []

      {:error, reason} ->
        ["✗ Channel lookup failed: #{inspect(reason)}"]
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true
end
