defmodule AshyWalnutDesk.AI.Adapters.Anthropic do
  @moduledoc """
  Req-direct Anthropic Messages API adapter (ADR-025, story 4.3).

  Implements the `AshyWalnutDesk.AI.Adapter` behaviour by POSTing an
  assembled `%AI.Prompt{}` to `https://api.anthropic.com/v1/messages`
  and normalizing the response into `%AI.Response{}`. No `ash_ai`; the
  HTTP envelope is owned here so prompt-caching markers and error
  classification are explicit and auditable.

  ## Prompt caching

  The assembler (story 4.2) emits `cache_control: %{type: "ephemeral"}`
  on the stable system blocks (framework + persona). This adapter
  forwards those markers verbatim — ephemeral caching is GA, so no
  `anthropic-beta` header is required. Note the minimum cacheable
  prefix is model-dependent and larger than the architecture's
  original "~1024" note: **Sonnet 4.6 needs ~2048 tokens, Opus 4.7
  needs ~4096**. A shorter prefix silently won't cache (no error;
  `cache_read_input_tokens` stays 0) — that's a PromptAssembler /
  Persona-content sizing concern, not an adapter bug.

  ## HTTP error classification (architecture §4.4)

  - `200` → `{:ok, %Response{}}`
  - `429` → `{:error, :rate_limited}` (caller backs off / Oban retries)
  - `5xx` → `{:error, :transient}`
  - `400` `invalid_request_error` → `{:error, :permanent}` (caller bug)
  - other `400` → `{:error, :content_blocked}` (provider safety stack)
  - `401/403/404/413` → `{:error, :permanent}` (config/permission — no retry)
  - transport timeout → `{:error, :timeout}`
  - other transport error → `{:error, :transient}`

  A content-policy refusal usually arrives as a `200` with
  `stop_reason: "refusal"` (not a 4xx) — that surfaces as
  `{:ok, %Response{stop_reason: "refusal"}}` and the worker (story 4.6)
  decides what to do.

  ## Model allowlist

  `complete/2` rejects any model not in `:ai_model_allowlist` with
  `{:error, {:model_not_allowed, model}}` **before** any network call,
  so a typo or an out-of-policy Persona override fails deterministically
  and for free.

  ## Test injection

  The HTTP layer is `Req`. Tests stub it by setting
  `:ashy_walnut_desk, :anthropic_req_options` (e.g.
  `plug: {Req.Test, AshyWalnutDesk.Anthropic}`) so no real network
  calls happen — mirrors the Twilio adapter's `:twilio_req_options`.
  """

  @behaviour AshyWalnutDesk.AI.Adapter

  require Logger

  alias AshyWalnutDesk.AI.{Prompt, Response}

  @messages_url "https://api.anthropic.com/v1/messages"
  @anthropic_version "2023-06-01"
  @default_max_tokens 1024

  @impl true
  def complete(%Prompt{} = prompt, opts \\ []) do
    model = opts[:model] || prompt.model || default_model()

    case validate_model(model) do
      :ok -> do_complete(prompt, model, opts)
      {:error, _} = error -> error
    end
  end

  defp do_complete(prompt, model, opts) do
    options = build_req_options(build_body(prompt, model), opts)

    case Req.post(@messages_url, options) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, normalize_success(body)}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, :transient}

      {:ok, %{status: 400, body: body}} ->
        classify_400(body)

      {:ok, %{status: status}} when status in 401..499 ->
        # auth / permission / not-found / payload-too-large — all
        # config or caller errors; retrying won't help.
        {:error, :permanent}

      {:error, %{__struct__: Req.TransportError, reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        Logger.warning("Adapters.Anthropic: transport error #{reason_tag(reason)}")
        {:error, :transient}
    end
  end

  # ────────────────────────────────────────────────────────────────
  # Request building
  # ────────────────────────────────────────────────────────────────

  defp build_body(%Prompt{} = prompt, model) do
    %{
      model: model,
      max_tokens: prompt.max_tokens || @default_max_tokens,
      system: render_system_blocks(prompt.system_blocks),
      messages: prompt.messages
    }
    |> maybe_put_metadata(prompt.metadata)
  end

  defp render_system_blocks(blocks) when is_list(blocks) do
    Enum.map(blocks, fn block ->
      base = %{type: Map.get(block, :type, "text"), text: Map.get(block, :text, "")}

      case Map.get(block, :cache_control) do
        nil -> base
        cache_control -> Map.put(base, :cache_control, cache_control)
      end
    end)
  end

  defp render_system_blocks(_), do: []

  # Anthropic's `metadata.user_id` is an opaque per-end-user string for
  # provider-side abuse detection. We pass the requesting operator's id
  # (never raw PII).
  defp maybe_put_metadata(body, metadata) when is_map(metadata) do
    case Map.get(metadata, :requestor_actor_id) || Map.get(metadata, "requestor_actor_id") do
      nil -> body
      actor_id -> Map.put(body, :metadata, %{user_id: to_string(actor_id)})
    end
  end

  defp maybe_put_metadata(body, _), do: body

  defp build_req_options(body, opts) do
    base = [
      headers: [
        {"x-api-key", api_key()},
        {"anthropic-version", @anthropic_version}
      ],
      json: body,
      receive_timeout: opts[:receive_timeout] || 60_000
    ]

    Keyword.merge(base, test_overrides())
  end

  defp test_overrides do
    Application.get_env(:ashy_walnut_desk, :anthropic_req_options, [])
  end

  # ────────────────────────────────────────────────────────────────
  # Response normalization
  # ────────────────────────────────────────────────────────────────

  defp normalize_success(body) when is_map(body) do
    %Response{
      text: extract_text(body),
      usage: extract_usage(body),
      stop_reason: body["stop_reason"] || body[:stop_reason],
      raw: body
    }
  end

  defp extract_text(body) do
    body
    |> Map.get("content", Map.get(body, :content, []))
    |> List.wrap()
    |> Enum.filter(fn block ->
      (block["type"] || block[:type]) == "text"
    end)
    |> Enum.map_join("", fn block -> block["text"] || block[:text] || "" end)
  end

  defp extract_usage(body) do
    usage = body["usage"] || body[:usage] || %{}

    %{
      input_tokens: usage_field(usage, "input_tokens"),
      output_tokens: usage_field(usage, "output_tokens"),
      cache_read_input_tokens: usage_field(usage, "cache_read_input_tokens"),
      cache_creation_input_tokens: usage_field(usage, "cache_creation_input_tokens")
    }
  end

  defp usage_field(usage, key) do
    usage[key] || usage[String.to_atom(key)] || 0
  end

  defp classify_400(body) when is_map(body) do
    error_type = get_in(body, ["error", "type"]) || get_in(body, [:error, :type])

    case error_type do
      "invalid_request_error" -> {:error, :permanent}
      _ -> {:error, :content_blocked}
    end
  end

  defp classify_400(_), do: {:error, :content_blocked}

  defp reason_tag(%{__struct__: mod}), do: inspect(mod)
  defp reason_tag(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_tag(reason) when is_binary(reason), do: reason
  defp reason_tag(_), do: "unknown"

  # ────────────────────────────────────────────────────────────────
  # Config + model allowlist
  # ────────────────────────────────────────────────────────────────

  defp validate_model(model) do
    allowed = Application.get_env(:ashy_walnut_desk, :ai_model_allowlist, [])

    if model in allowed do
      :ok
    else
      {:error, {:model_not_allowed, model}}
    end
  end

  defp default_model do
    Application.get_env(:ashy_walnut_desk, :default_model, "claude-sonnet-4-6")
  end

  defp api_key do
    anthropic_config(:api_key) || System.get_env("ANTHROPIC_API_KEY") ||
      fallback_key!()
  end

  defp anthropic_config(key) do
    :ashy_walnut_desk
    |> Application.get_env(:anthropic, [])
    |> Keyword.get(key)
  end

  # Mirrors `Adapters.Twilio.fallback_credential!/1`. In `:prod` this
  # branch is unreachable — `config/runtime.exs` raises at boot if
  # `ANTHROPIC_API_KEY` is unset. In dev/test the Fixture adapter is
  # the default, so this placeholder never reaches a real request
  # (test HTTP is stubbed at the Req plug boundary).
  defp fallback_key! do
    case Application.fetch_env(:ashy_walnut_desk, :env) do
      {:ok, :prod} ->
        raise """
        Adapters.Anthropic: missing ANTHROPIC_API_KEY.
        This branch should be unreachable in :prod — config/runtime.exs
        is supposed to raise at boot. Investigate config drift.
        """

      _ ->
        "DEV_PLACEHOLDER_ANTHROPIC_API_KEY"
    end
  end
end
