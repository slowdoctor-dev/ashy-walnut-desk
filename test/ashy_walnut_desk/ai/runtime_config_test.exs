defmodule AshyWalnutDesk.AI.RuntimeConfigTest do
  @moduledoc """
  Story 4.3 AC4 — Anthropic key resolution semantics. The adapter
  prefers the `:anthropic` config keyword, then the `ANTHROPIC_API_KEY`
  env var, then a dev/test placeholder. In `:prod` a missing key raises
  (defensive; `config/runtime.exs` already fails fast at boot).
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.AI.Adapters.Anthropic
  alias AshyWalnutDesk.AI.Prompt

  setup do
    prev_req = Application.get_env(:ashy_walnut_desk, :anthropic_req_options, [])
    prev_anthropic = Application.get_env(:ashy_walnut_desk, :anthropic)
    prev_env = Application.fetch_env(:ashy_walnut_desk, :env)
    prev_api_key = System.get_env("ANTHROPIC_API_KEY")

    on_exit(fn ->
      Application.put_env(:ashy_walnut_desk, :anthropic_req_options, prev_req)
      restore(:anthropic, prev_anthropic)

      case prev_env do
        {:ok, value} -> Application.put_env(:ashy_walnut_desk, :env, value)
        :error -> Application.delete_env(:ashy_walnut_desk, :env)
      end

      case prev_api_key do
        nil -> System.delete_env("ANTHROPIC_API_KEY")
        value -> System.put_env("ANTHROPIC_API_KEY", value)
      end
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:ashy_walnut_desk, key)
  defp restore(key, value), do: Application.put_env(:ashy_walnut_desk, key, value)

  defp prompt do
    %Prompt{
      model: "claude-sonnet-4-6",
      max_tokens: 64,
      system_blocks: [%{type: "text", text: "Rules."}],
      messages: [%{role: "user", content: "Hi"}],
      metadata: %{}
    }
  end

  defp capture_key_plug(test_pid) do
    [
      plug: fn conn ->
        send(test_pid, {:api_key, Map.new(conn.req_headers)["x-api-key"]})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"content" => [%{"type" => "text", "text" => "ok"}], "usage" => %{}})
        )
      end
    ]
  end

  test "reads the api key from the :anthropic config keyword" do
    Application.put_env(:ashy_walnut_desk, :anthropic, api_key: "sk-from-config")
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options, capture_key_plug(self()))

    assert {:ok, _} = Anthropic.complete(prompt())
    assert_received {:api_key, "sk-from-config"}
  end

  test "uses a dev placeholder when unconfigured outside :prod" do
    Application.delete_env(:ashy_walnut_desk, :anthropic)
    Application.delete_env(:ashy_walnut_desk, :env)
    System.delete_env("ANTHROPIC_API_KEY")
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options, capture_key_plug(self()))

    assert {:ok, _} = Anthropic.complete(prompt())
    assert_received {:api_key, key}
    assert key =~ "DEV_PLACEHOLDER"
  end

  test "raises in :prod when the key is missing (defensive fail-fast)" do
    Application.delete_env(:ashy_walnut_desk, :anthropic)
    System.delete_env("ANTHROPIC_API_KEY")
    Application.put_env(:ashy_walnut_desk, :env, :prod)

    assert_raise RuntimeError, ~r/ANTHROPIC_API_KEY/, fn ->
      Anthropic.complete(prompt())
    end
  end
end
