defmodule Mix.Tasks.Phase3.Webhook.PreflightTest do
  @moduledoc """
  Story 3.1 — AC1 (missing env → non-zero exit) + AC2 (full env +
  channel row → zero exit). The task uses `Mix.raise/1` on failure;
  ExUnit asserts the raise via `assert_raise Mix.Error`.
  """

  use AshyWalnutDesk.DataCase, async: false

  import ExUnit.CaptureIO

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Channel

  @required_env_vars ~w(TWILIO_ACCOUNT_SID TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER)

  setup do
    originals = Map.new(@required_env_vars, fn k -> {k, System.get_env(k)} end)
    Enum.each(@required_env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(originals, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)
    end)

    :ok
  end

  test "missing env vars → Mix.raise (non-zero exit on the CLI)" do
    Mix.Task.reenable("phase3.webhook.preflight")

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/phase3.webhook.preflight: 4 check\(s\) failed/, fn ->
          Mix.Task.run("phase3.webhook.preflight")
        end
      end)

    assert captured =~ "missing env var: TWILIO_ACCOUNT_SID"
    assert captured =~ "missing env var: TWILIO_AUTH_TOKEN"
    assert captured =~ "missing env var: TWILIO_FROM_NUMBER"
    assert captured =~ "Channel{slug: \"twilio-sms\"} is not registered"
  end

  test "env present but channel missing → still raises on the channel check" do
    Enum.each(@required_env_vars, fn k -> System.put_env(k, "dev-only-#{k}") end)

    Mix.Task.reenable("phase3.webhook.preflight")

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> Mix.Task.run("phase3.webhook.preflight") end
      end)

    refute captured =~ "missing env var:"
    assert captured =~ "Channel{slug: \"twilio-sms\"} is not registered"
  end

  test "all env vars + registered twilio-sms channel → ok message, no raise" do
    Enum.each(@required_env_vars, fn k -> System.put_env(k, "dev-only-#{k}") end)

    admin = AccountsFixtures.create_user(:admin)

    {:ok, _channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    Mix.Task.reenable("phase3.webhook.preflight")

    captured =
      capture_io(fn ->
        Mix.Task.run("phase3.webhook.preflight")
      end)

    assert captured =~ "✓ phase3.webhook.preflight ok"
  end

  test "disabled twilio-sms channel → raises with re-enable hint" do
    Enum.each(@required_env_vars, fn k -> System.put_env(k, "dev-only-#{k}") end)

    admin = AccountsFixtures.create_user(:admin)

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "twilio-sms",
          display_name: "Twilio SMS",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, _disabled} = Ash.update(channel, %{}, action: :disable, actor: admin)

    Mix.Task.reenable("phase3.webhook.preflight")

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> Mix.Task.run("phase3.webhook.preflight") end
      end)

    assert captured =~ "exists but is disabled"
  end
end
