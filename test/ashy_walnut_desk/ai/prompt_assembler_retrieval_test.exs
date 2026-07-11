defmodule AshyWalnutDesk.AI.PromptAssemblerRetrievalTest do
  @moduledoc """
  Story 5.5 AC1 — retrieved excerpts render as one appended system
  block with `[slug rN §pos]` headers, without `cache_control`, and the
  cached framework/persona blocks stay byte-identical with and without
  retrieval (Phase 4 cache-stability AC preserved).
  """

  use ExUnit.Case, async: true

  alias AshyWalnutDesk.AI.PromptAssembler
  alias AshyWalnutDesk.Knowledge.RetrievalResult

  defp base_input do
    %{
      persona: %{
        system_prompt: String.duplicate("stable persona prompt ", 8),
        guardrail_notes: "No unsupported claims.",
        disclosure_text: "AI-assisted."
      },
      messages: [
        %{direction: :inbound, body: "Can you confirm my appointment?", inserted_at: nil}
      ],
      model: "claude-sonnet-4-6"
    }
  end

  defp retrieval do
    %RetrievalResult{
      mode: :vector,
      excerpts: [
        %{
          manual_id: "m-1",
          manual_slug: "front-desk",
          revision: 3,
          position: 1,
          content: "Confirm the requested time before promising anything.",
          content_hash: "hash-1",
          score: 0.91,
          embedder: "fixture"
        },
        %{
          manual_id: "m-2",
          manual_slug: "escalation",
          revision: 1,
          position: 0,
          content: "Escalate billing disputes to the admin.",
          content_hash: "hash-2",
          score: 0.72,
          embedder: "fixture"
        }
      ]
    }
  end

  test "appends exactly one non-cached knowledge block with per-excerpt headers" do
    {:ok, prompt} = PromptAssembler.build(Map.put(base_input(), :retrieval, retrieval()))

    assert [_framework, _persona, _conversation, knowledge] = prompt.system_blocks

    refute Map.has_key?(knowledge, :cache_control)
    assert knowledge.text =~ "[Deployment Knowledge]"
    assert knowledge.text =~ "[front-desk r3 §1] Confirm the requested time"
    assert knowledge.text =~ "[escalation r1 §0] Escalate billing disputes"
  end

  test "cached blocks are byte-identical with and without retrieval" do
    {:ok, without} = PromptAssembler.build(base_input())
    {:ok, with_retrieval} = PromptAssembler.build(Map.put(base_input(), :retrieval, retrieval()))

    assert Enum.take(without.system_blocks, 2) == Enum.take(with_retrieval.system_blocks, 2)

    assert Enum.all?(Enum.take(with_retrieval.system_blocks, 2), fn block ->
             block.cache_control == %{type: "ephemeral"}
           end)
  end

  test "nil retrieval and empty excerpts add no block" do
    {:ok, no_key} = PromptAssembler.build(base_input())
    {:ok, nil_retrieval} = PromptAssembler.build(Map.put(base_input(), :retrieval, nil))

    {:ok, empty} =
      PromptAssembler.build(
        Map.put(base_input(), :retrieval, %RetrievalResult{mode: :none, excerpts: []})
      )

    assert length(no_key.system_blocks) == 3
    assert nil_retrieval.system_blocks == no_key.system_blocks
    assert empty.system_blocks == no_key.system_blocks
  end
end
