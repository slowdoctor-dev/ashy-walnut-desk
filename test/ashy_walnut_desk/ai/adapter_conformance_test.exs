defmodule AshyWalnutDesk.AI.AdapterConformanceTest do
  @moduledoc """
  Story 4.3 AC3 — both the Fixture (story 4.2) and Anthropic (story
  4.3) adapters satisfy the same `AI.Adapter` contract: `complete/2`
  returns either `{:ok, %Response{}}` with a string `text` + map
  `usage`, or `{:error, reason}` where `reason` is drawn from the
  declared error set. Anthropic's network layer is stubbed at the Req
  plug boundary; Fixture is deterministic.
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.AI.Adapters.{Anthropic, Fixture}
  alias AshyWalnutDesk.AI.{Prompt, Response}

  @adapters [Anthropic, Fixture]
  @error_reasons [:transient, :permanent, :rate_limited, :content_blocked, :timeout]

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :anthropic_req_options, [])

    Application.put_env(:ashy_walnut_desk, :anthropic_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "content" => [%{"type" => "text", "text" => "conformant"}],
            "stop_reason" => "end_turn",
            "usage" => %{"input_tokens" => 5, "output_tokens" => 3}
          })
        )
      end
    )

    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :anthropic_req_options, prev) end)
    :ok
  end

  defp prompt do
    %Prompt{
      model: "claude-sonnet-4-6",
      max_tokens: 64,
      system_blocks: [%{type: "text", text: "Rules.", cache_control: %{type: "ephemeral"}}],
      messages: [%{role: "user", content: "Hi"}],
      metadata: %{}
    }
  end

  test "every adapter implements the AI.Adapter behaviour" do
    for adapter <- @adapters do
      behaviours = adapter.module_info(:attributes)[:behaviour] || []

      assert AshyWalnutDesk.AI.Adapter in behaviours,
             "#{inspect(adapter)} must @behaviour AI.Adapter"

      assert function_exported?(adapter, :complete, 2)
    end
  end

  test "every adapter returns a shape-conformant ok/error result" do
    for adapter <- @adapters do
      case adapter.complete(prompt()) do
        {:ok, %Response{} = response} ->
          assert is_binary(response.text)
          assert is_map(response.usage)

        {:error, reason} ->
          assert reason in @error_reasons,
                 "#{inspect(adapter)} returned unexpected error #{inspect(reason)}"
      end
    end
  end

  test "the Anthropic adapter's error classes stay within the contract" do
    cases = [
      {429, %{"error" => %{"type" => "rate_limit_error"}}, :rate_limited},
      {503, %{"error" => %{"type" => "overloaded_error"}}, :transient},
      {400, %{"error" => %{"type" => "invalid_request_error"}}, :permanent},
      {400, %{"error" => %{"type" => "request_blocked"}}, :content_blocked}
    ]

    for {status, body, expected} <- cases do
      Application.put_env(:ashy_walnut_desk, :anthropic_req_options,
        plug: fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(status, Jason.encode!(body))
        end
      )

      assert {:error, ^expected} = Anthropic.complete(prompt())
      assert expected in @error_reasons
    end
  end
end
