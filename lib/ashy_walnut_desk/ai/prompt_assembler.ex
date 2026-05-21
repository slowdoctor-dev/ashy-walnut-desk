defmodule AshyWalnutDesk.AI.PromptAssembler do
  @moduledoc false

  alias AshyWalnutDesk.AI.Prompt
  alias AshyWalnutDesk.Knowledge.Persona

  @framework_text """
  You are assisting a front-desk operator by drafting a message.
  You do not send messages and must assume a human reviews all output.
  Avoid unsupported domain assertions, guarantees, or professional claims.
  Keep drafts concise, factual, and safe for operator review.
  """

  @framework_header "[Framework Rules]"
  @persona_header "[Persona Instructions]"
  @conversation_header "[Conversation Context]"
  @cache_control %{type: "ephemeral"}
  @persona_max_chars 12_000
  @conversation_token_ceiling 4_000
  @history_limit 20
  @truncated_sentinel "[earlier history truncated]"

  @type build_input :: %{
          required(:persona) => Persona.t() | map(),
          required(:messages) => [map()],
          optional(:model) => String.t(),
          optional(:max_tokens) => pos_integer(),
          optional(:metadata) => map(),
          optional(:user_message) => String.t()
        }

  @spec build(build_input()) :: {:ok, Prompt.t()} | {:error, term()}
  def build(%{persona: persona, messages: messages} = attrs) when is_list(messages) do
    with {:ok, persona_text} <- build_persona_text(persona) do
      conversation_lines =
        messages |> Enum.take(-@history_limit) |> Enum.map(&render_transcript_line/1)

      conversation_text = trim_conversation(conversation_lines)

      user_message = attrs[:user_message] || latest_inbound_body(messages)

      {:ok,
       %Prompt{
         model: attrs[:model],
         max_tokens: attrs[:max_tokens],
         system_blocks: [
           %{type: "text", text: framework_text(), cache_control: @cache_control},
           %{type: "text", text: persona_text, cache_control: @cache_control},
           %{type: "text", text: conversation_text}
         ],
         messages: [%{role: "user", content: user_message}],
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  def build(_), do: {:error, :invalid_input}

  defp framework_text do
    [@framework_header, String.trim(@framework_text)]
    |> Enum.join("\n\n")
  end

  defp build_persona_text(persona) do
    system_prompt = read_persona_field(persona, :system_prompt)
    guardrail_notes = read_persona_field(persona, :guardrail_notes)

    text =
      [
        @persona_header,
        String.trim(system_prompt || ""),
        if(is_binary(guardrail_notes) and String.trim(guardrail_notes) != "",
          do: "Guardrail notes:\n" <> String.trim(guardrail_notes),
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    if String.length(text) > @persona_max_chars do
      {:error, :persona_block_too_large}
    else
      {:ok, text}
    end
  end

  defp trim_conversation(lines) do
    kept = keep_within_budget(lines)
    body = Enum.join(kept, "\n")

    [@conversation_header, body]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp keep_within_budget(lines) do
    reversed = Enum.reverse(lines)

    {kept_rev, dropped?} =
      Enum.reduce_while(reversed, {[], false}, fn line, {acc, _dropped} ->
        candidate = [line | acc] |> Enum.reverse()

        if estimate_tokens(Enum.join(candidate, "\n")) <= @conversation_token_ceiling do
          {:cont, {[line | acc], false}}
        else
          {:halt, {acc, true}}
        end
      end)

    kept = Enum.reverse(kept_rev)

    if dropped? and kept != [] do
      [@truncated_sentinel | kept]
    else
      kept
    end
  end

  defp estimate_tokens(text), do: max(1, div(String.length(text), 4))

  defp render_transcript_line(message) do
    direction =
      case Map.get(message, :direction) || Map.get(message, "direction") do
        :outbound -> "Outbound"
        "outbound" -> "Outbound"
        _ -> "Inbound"
      end

    timestamp =
      format_timestamp(Map.get(message, :inserted_at) || Map.get(message, "inserted_at"))

    body = Map.get(message, :body) || Map.get(message, "body") || ""

    "#{direction} (#{timestamp}): #{body}"
  end

  defp format_timestamp(nil), do: "unknown"

  defp format_timestamp(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  end

  defp format_timestamp(value) when is_binary(value), do: value
  defp format_timestamp(_), do: "unknown"

  defp latest_inbound_body(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn message ->
      direction = Map.get(message, :direction) || Map.get(message, "direction")

      if direction in [:inbound, "inbound", nil] do
        Map.get(message, :body) || Map.get(message, "body")
      end
    end)
    |> Kernel.||("")
  end

  defp read_persona_field(%_{} = persona, key), do: Map.get(persona, key)
  defp read_persona_field(persona, key) when is_map(persona), do: Map.get(persona, key)
end
