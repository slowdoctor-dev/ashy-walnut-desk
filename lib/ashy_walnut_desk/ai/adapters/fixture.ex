defmodule AshyWalnutDesk.AI.Adapters.Fixture do
  @moduledoc """
  Deterministic adapter for tests and local development.

  Response text is selected from a fixed set based on a stable hash of
  the `%AI.Prompt{}` payload. Optional simulated latency can be provided
  per-call (`:latency_ms`) or via app config (`:ai_fixture_latency_ms`).
  """

  @behaviour AshyWalnutDesk.AI.Adapter

  alias AshyWalnutDesk.AI.{Prompt, Response}

  @fallback_text "Fixture response: please review and edit before sending."

  @canned_responses [
    "Fixture response A: acknowledged. I drafted a concise follow-up.",
    "Fixture response B: I summarized the request and proposed next steps.",
    "Fixture response C: I drafted a compliant, operator-reviewable reply."
  ]

  @impl true
  def complete(%Prompt{} = prompt, opts \\ []) do
    maybe_sleep(opts)

    hash = :erlang.phash2(prompt)
    text = Enum.at(@canned_responses, rem(hash, length(@canned_responses)), @fallback_text)

    {:ok,
     %Response{
       text: text,
       usage: %{
         input_tokens: estimate_tokens(prompt),
         output_tokens: estimate_tokens(text),
         cache_read_input_tokens: 0,
         cache_creation_input_tokens: 0
       },
       stop_reason: "end_turn",
       raw: %{fixture: true, prompt_hash: hash}
     }}
  end

  defp maybe_sleep(opts) do
    latency_ms =
      Keyword.get(
        opts,
        :latency_ms,
        Application.get_env(:ashy_walnut_desk, :ai_fixture_latency_ms, 0)
      )

    if is_integer(latency_ms) and latency_ms > 0 do
      Process.sleep(latency_ms)
    end
  end

  defp estimate_tokens(%Prompt{} = prompt) do
    source =
      [
        prompt.model || "",
        Enum.map_join(prompt.system_blocks, "\n", &Map.get(&1, :text, "")),
        Enum.map_join(prompt.messages, "\n", &Map.get(&1, :content, ""))
      ]
      |> Enum.join("\n")

    estimate_tokens(source)
  end

  defp estimate_tokens(text) when is_binary(text) do
    max(1, div(String.length(text), 4))
  end
end
