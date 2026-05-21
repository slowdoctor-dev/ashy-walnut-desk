defmodule AshyWalnutDesk.AI.PromptAssemblerTest do
  use ExUnit.Case, async: true

  alias AshyWalnutDesk.AI.PromptAssembler

  test "build/1 emits three system blocks with cache_control only on framework and persona" do
    persona = %{
      system_prompt: "Use calm and clear tone.",
      guardrail_notes: "Do not promise outcomes."
    }

    now = DateTime.utc_now()

    messages = [
      %{direction: :inbound, inserted_at: now, body: "Hi there"},
      %{direction: :outbound, inserted_at: now, body: "Hello"}
    ]

    assert {:ok, prompt} =
             PromptAssembler.build(%{
               persona: persona,
               messages: messages,
               model: "claude-sonnet-4-6",
               max_tokens: 500,
               metadata: %{draft_id: "draft-1"}
             })

    assert length(prompt.system_blocks) == 3
    [framework, persona_block, conversation] = prompt.system_blocks

    assert framework.cache_control == %{type: "ephemeral"}
    assert persona_block.cache_control == %{type: "ephemeral"}
    refute Map.has_key?(conversation, :cache_control)

    assert String.contains?(framework.text, "[Framework Rules]")
    assert String.contains?(persona_block.text, "[Persona Instructions]")
    assert String.contains?(conversation.text, "[Conversation Context]")
    assert String.contains?(conversation.text, "Inbound")
    assert String.contains?(conversation.text, "Outbound")
  end

  test "build/1 rejects oversized persona block" do
    persona = %{system_prompt: String.duplicate("a", 12_100), guardrail_notes: ""}

    assert {:error, :persona_block_too_large} =
             PromptAssembler.build(%{persona: persona, messages: []})
  end

  test "build/1 trims conversation with sentinel when over budget" do
    persona = %{system_prompt: "Prompt", guardrail_notes: nil}

    messages =
      for i <- 1..20 do
        %{
          direction: :inbound,
          inserted_at: DateTime.utc_now(),
          body: "msg#{i}-" <> String.duplicate("x", 1_500)
        }
      end

    assert {:ok, prompt} = PromptAssembler.build(%{persona: persona, messages: messages})
    [_, _, conversation] = prompt.system_blocks

    assert String.contains?(conversation.text, "[earlier history truncated]")
  end

  test "build/1 user message defaults to latest inbound body" do
    messages = [
      %{direction: :outbound, inserted_at: DateTime.utc_now(), body: "sent"},
      %{direction: :inbound, inserted_at: DateTime.utc_now(), body: "latest inbound"}
    ]

    assert {:ok, prompt} =
             PromptAssembler.build(%{
               persona: %{system_prompt: "prompt", guardrail_notes: nil},
               messages: messages
             })

    assert [%{role: "user", content: "latest inbound"}] = prompt.messages
  end
end
