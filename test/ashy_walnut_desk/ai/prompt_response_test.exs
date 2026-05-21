defmodule AshyWalnutDesk.AI.PromptResponseTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.AI.{Prompt, Response}

  test "prompt struct exposes architecture fields" do
    prompt = %Prompt{
      model: "claude-sonnet-4-6",
      max_tokens: 512,
      system_blocks: [%{type: "text", text: "framework", cache_control: %{type: "ephemeral"}}],
      messages: [%{role: "user", content: "hello"}],
      metadata: %{draft_id: "d1", persona_id: "p1", requestor_actor_id: "u1"}
    }

    assert prompt.model == "claude-sonnet-4-6"
    assert prompt.max_tokens == 512
    assert [%{type: "text"}] = prompt.system_blocks
    assert [%{role: "user", content: "hello"}] = prompt.messages
    assert prompt.metadata.requestor_actor_id == "u1"
  end

  test "response struct exposes text usage and stop reason" do
    response = %Response{
      text: "draft body",
      usage: %{input_tokens: 100, output_tokens: 55},
      stop_reason: "end_turn",
      raw: %{provider: :fixture}
    }

    assert response.text == "draft body"
    assert response.usage.input_tokens == 100
    assert response.usage.output_tokens == 55
    assert response.stop_reason == "end_turn"
    assert response.raw.provider == :fixture
  end
end
