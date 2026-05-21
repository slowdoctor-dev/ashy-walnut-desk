defmodule AshyWalnutDesk.AI.AdapterContractTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.AI.Adapters.Fixture
  alias AshyWalnutDesk.AI.{Prompt, Response}

  test "fixture conforms to AI.Adapter.complete/2 return contract" do
    prompt = %Prompt{
      model: "claude-sonnet-4-6",
      max_tokens: 400,
      system_blocks: [%{type: "text", text: "framework", cache_control: %{type: "ephemeral"}}],
      messages: [%{role: "user", content: "Please help"}],
      metadata: %{draft_id: "draft-1"}
    }

    assert {:ok, %Response{} = response} = Fixture.complete(prompt, latency_ms: 0)
    assert is_binary(response.text)
    assert response.stop_reason == "end_turn"
    assert is_map(response.usage)
  end

  test "fixture is deterministic for same prompt" do
    prompt = %Prompt{
      model: "claude-opus-4-7",
      max_tokens: 400,
      system_blocks: [%{type: "text", text: "framework", cache_control: %{type: "ephemeral"}}],
      messages: [%{role: "user", content: "Same prompt"}],
      metadata: %{draft_id: "draft-2"}
    }

    assert {:ok, first} = Fixture.complete(prompt, latency_ms: 0)
    assert {:ok, second} = Fixture.complete(prompt, latency_ms: 0)
    assert first.text == second.text
    assert first.raw == second.raw
  end
end
