defmodule Mix.Tasks.Phase4.Ai.PreflightTest do
  @moduledoc """
  Story 4.8 AC1 — `mix phase4.ai.preflight` fails fast (non-zero exit
  via `Mix.raise/1`) on missing/invalid AI runtime configuration and
  supports an offline `--skip-network` mode. The Anthropic health check
  is stubbed at the Req plug boundary (`:anthropic_req_options`) so no
  real network calls happen.
  """

  use AshyWalnutDesk.DataCase, async: false

  import ExUnit.CaptureIO

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Knowledge.Persona

  @app_keys ~w(default_model ai_adapter ai_model_allowlist
               ai_adapter_allowlist anthropic anthropic_req_options)a

  setup do
    original_key = System.get_env("ANTHROPIC_API_KEY")
    originals = Map.new(@app_keys, fn k -> {k, Application.fetch_env(:ashy_walnut_desk, k)} end)

    on_exit(fn ->
      restore_env_var("ANTHROPIC_API_KEY", original_key)

      Enum.each(originals, fn
        {k, {:ok, v}} -> Application.put_env(:ashy_walnut_desk, k, v)
        {k, :error} -> Application.delete_env(:ashy_walnut_desk, k)
      end)
    end)

    System.delete_env("ANTHROPIC_API_KEY")
    Application.delete_env(:ashy_walnut_desk, :anthropic)
    :ok
  end

  defp restore_env_var(name, nil), do: System.delete_env(name)
  defp restore_env_var(name, value), do: System.put_env(name, value)

  defp run_preflight(argv) do
    Mix.Task.reenable("phase4.ai.preflight")
    Mix.Task.run("phase4.ai.preflight", argv)
  end

  defp stub_anthropic(fun) do
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options, plug: fun)
  end

  test "missing ANTHROPIC_API_KEY → Mix.raise (non-zero exit on the CLI)" do
    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/phase4.ai.preflight: 1 check\(s\) failed/, fn ->
          run_preflight(["--skip-network"])
        end
      end)

    assert captured =~ "missing ANTHROPIC_API_KEY"
  end

  test ":default_model outside :ai_model_allowlist → raises" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-preflight-key")
    Application.put_env(:ashy_walnut_desk, :default_model, "claude-nonexistent-0-0")

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> run_preflight(["--skip-network"]) end
      end)

    assert captured =~ ":default_model \"claude-nonexistent-0-0\" is not in :ai_model_allowlist"
  end

  test ":ai_adapter outside :ai_adapter_allowlist → raises" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-preflight-key")
    Application.put_env(:ashy_walnut_desk, :ai_adapter, NotAReal.Adapter)

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> run_preflight(["--skip-network"]) end
      end)

    assert captured =~ ":ai_adapter NotAReal.Adapter is not in :ai_adapter_allowlist"
  end

  test "Persona model_override stranded outside a shrunk allowlist → raises" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-preflight-key")
    admin = AccountsFixtures.create_user(:admin)

    {:ok, _persona} =
      Ash.create(
        Persona,
        %{
          name: "Opus Persona",
          slug: "opus-persona-#{System.unique_integer([:positive])}",
          system_prompt: String.duplicate("safe prompt ", 8),
          disclosure_text: "AI-assisted draft.",
          model_override: "claude-opus-4-7"
        },
        action: :create,
        actor: admin
      )

    Application.put_env(:ashy_walnut_desk, :ai_model_allowlist, ["claude-sonnet-4-6"])

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn -> run_preflight(["--skip-network"]) end
      end)

    assert captured =~ "model_override \"claude-opus-4-7\" outside :ai_model_allowlist"
  end

  test "valid config + --skip-network → ok, no HTTP attempted" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-preflight-key")

    stub_anthropic(fn _conn -> flunk("network check must not run under --skip-network") end)

    captured = capture_io(fn -> run_preflight(["--skip-network"]) end)

    assert captured =~ "✓ phase4.ai.preflight ok (network check skipped)"
  end

  test "valid config + healthy provider → ok with reachability note" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-preflight-key")
    Process.put(:preflight_health_hits, 0)

    stub_anthropic(fn conn ->
      Process.put(:preflight_health_hits, Process.get(:preflight_health_hits) + 1)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "content" => [%{"type" => "text", "text" => "y"}],
          "stop_reason" => "max_tokens",
          "usage" => %{"input_tokens" => 12, "output_tokens" => 1}
        })
      )
    end)

    captured = capture_io(fn -> run_preflight([]) end)

    assert captured =~ "✓ phase4.ai.preflight ok (Anthropic reachable)"
    assert Process.get(:preflight_health_hits) == 1
  end

  test "valid config but provider rejects the key → raises with actionable hint" do
    System.put_env("ANTHROPIC_API_KEY", "dev-only-revoked-key")

    stub_anthropic(fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        401,
        Jason.encode!(%{"error" => %{"type" => "authentication_error"}})
      )
    end)

    captured =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, ~r/phase4.ai.preflight: 1 check\(s\) failed/, fn ->
          run_preflight([])
        end
      end)

    assert captured =~ "Anthropic health check failed"
    assert captured =~ "verify ANTHROPIC_API_KEY validity/permissions"
  end
end
