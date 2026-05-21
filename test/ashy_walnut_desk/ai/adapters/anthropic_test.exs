defmodule AshyWalnutDesk.AI.Adapters.AnthropicTest do
  @moduledoc """
  Story 4.3 AC1 — the Req-direct Anthropic adapter implements
  `AI.Adapter.complete/2` with the correct request envelope (headers,
  cache_control forwarding) and normalized response shape, plus the
  HTTP-status → error-class mapping from architecture §4.4. The HTTP
  layer is stubbed at the `Req` plug boundary (`:anthropic_req_options`)
  so no real network calls happen.
  """

  use ExUnit.Case, async: false

  alias AshyWalnutDesk.AI.Adapters.Anthropic
  alias AshyWalnutDesk.AI.{Prompt, Response}

  setup do
    prev = Application.get_env(:ashy_walnut_desk, :anthropic_req_options, [])
    on_exit(fn -> Application.put_env(:ashy_walnut_desk, :anthropic_req_options, prev) end)
    :ok
  end

  defp stub_with(fun) do
    Application.put_env(:ashy_walnut_desk, :anthropic_req_options, plug: fun)
  end

  defp respond(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp sample_prompt do
    %Prompt{
      model: "claude-sonnet-4-6",
      max_tokens: 256,
      system_blocks: [
        %{type: "text", text: "Framework rules.", cache_control: %{type: "ephemeral"}},
        %{type: "text", text: "Conversation context."}
      ],
      messages: [%{role: "user", content: "Hello"}],
      metadata: %{requestor_actor_id: "operator-123"}
    }
  end

  defp success_body do
    %{
      "content" => [%{"type" => "text", "text" => "Drafted reply."}],
      "stop_reason" => "end_turn",
      "usage" => %{
        "input_tokens" => 120,
        "output_tokens" => 42,
        "cache_read_input_tokens" => 1024,
        "cache_creation_input_tokens" => 0
      }
    }
  end

  test "success normalizes content, usage, and stop_reason" do
    stub_with(fn conn -> respond(conn, 200, success_body()) end)

    assert {:ok, %Response{} = response} = Anthropic.complete(sample_prompt())
    assert response.text == "Drafted reply."
    assert response.stop_reason == "end_turn"
    assert response.usage.input_tokens == 120
    assert response.usage.output_tokens == 42
    assert response.usage.cache_read_input_tokens == 1024
    assert response.usage.cache_creation_input_tokens == 0
    assert is_map(response.raw)
  end

  test "request carries auth/version headers and forwards cache_control markers" do
    test_pid = self()

    stub_with(fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:captured, Map.new(conn.req_headers), Jason.decode!(raw)})
      respond(conn, 200, success_body())
    end)

    assert {:ok, _} = Anthropic.complete(sample_prompt())

    assert_received {:captured, headers, body}
    assert headers["x-api-key"] != nil
    assert headers["anthropic-version"] == "2023-06-01"

    assert body["model"] == "claude-sonnet-4-6"
    assert body["max_tokens"] == 256
    # First system block keeps its ephemeral cache marker; second has none.
    assert [first, second] = body["system"]
    assert first["cache_control"] == %{"type" => "ephemeral"}
    refute Map.has_key?(second, "cache_control")
    # Operator id flows into metadata.user_id (never raw PII).
    assert body["metadata"]["user_id"] == "operator-123"
  end

  test "429 maps to :rate_limited" do
    stub_with(fn conn -> respond(conn, 429, %{"error" => %{"type" => "rate_limit_error"}}) end)
    assert {:error, :rate_limited} = Anthropic.complete(sample_prompt())
  end

  test "5xx maps to :transient" do
    stub_with(fn conn -> respond(conn, 503, %{"error" => %{"type" => "overloaded_error"}}) end)
    assert {:error, :transient} = Anthropic.complete(sample_prompt())
  end

  test "400 invalid_request_error maps to :permanent" do
    stub_with(fn conn ->
      respond(conn, 400, %{"error" => %{"type" => "invalid_request_error", "message" => "bad"}})
    end)

    assert {:error, :permanent} = Anthropic.complete(sample_prompt())
  end

  test "other 400 maps to :content_blocked" do
    stub_with(fn conn ->
      respond(conn, 400, %{"error" => %{"type" => "request_blocked", "message" => "policy"}})
    end)

    assert {:error, :content_blocked} = Anthropic.complete(sample_prompt())
  end

  test "401 maps to :permanent (config error, no retry)" do
    stub_with(fn conn -> respond(conn, 401, %{"error" => %{"type" => "authentication_error"}}) end)

    assert {:error, :permanent} = Anthropic.complete(sample_prompt())
  end

  test "transport timeout maps to :timeout" do
    stub_with(fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, :timeout} = Anthropic.complete(sample_prompt())
  end

  test "other transport error maps to :transient" do
    stub_with(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, :transient} = Anthropic.complete(sample_prompt())
  end
end
