defmodule AshyWalnutDesk.AI.ModelAllowlistTest do
  @moduledoc """
  Story 4.3 AC2 — model allowlist + default-model enforcement. A model
  outside `:ai_model_allowlist` is rejected deterministically *before*
  any network call; the configured `:default_model` is itself a member
  of the allowlist so the no-override path always succeeds.
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.AI.Adapters.Anthropic
  alias AshyWalnutDesk.AI.Prompt

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :anthropic_req_options, [])
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :anthropic_req_options, prev) end)
    :ok
  end

  defp prompt(attrs \\ []) do
    %Prompt{
      model: Keyword.get(attrs, :model),
      max_tokens: 64,
      system_blocks: [%{type: "text", text: "Rules."}],
      messages: [%{role: "user", content: "Hi"}],
      metadata: %{}
    }
  end

  test "a disallowed model is rejected with no HTTP call" do
    # No Req stub is configured; if the adapter attempted a request it
    # would hit the real network. It must short-circuit instead.
    assert {:error, {:model_not_allowed, "gpt-imaginary"}} =
             Anthropic.complete(prompt(model: "gpt-imaginary"))
  end

  test "the configured default_model is a member of the allowlist" do
    default = Application.get_env(:ashy_walnut_desk, :default_model)
    allowed = Application.get_env(:ashy_walnut_desk, :ai_model_allowlist)
    assert default in allowed
  end

  test "an explicit allowlisted model passes validation and reaches the provider" do
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "content" => [%{"type" => "text", "text" => "ok"}],
            "stop_reason" => "end_turn",
            "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
          })
        )
      end
    )

    [allowed | _] = Application.get_env(:ashy_walnut_desk, :ai_model_allowlist)
    assert {:ok, _response} = Anthropic.complete(prompt(model: allowed))
  end

  test "nil model falls back to the default and is allowed" do
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"content" => [%{"type" => "text", "text" => "ok"}], "usage" => %{}})
        )
      end
    )

    assert {:ok, _response} = Anthropic.complete(prompt(model: nil))
  end
end
