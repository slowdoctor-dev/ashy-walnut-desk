defmodule AshyWalnutDesk.Knowledge.Embedders.Voyage do
  @moduledoc """
  Req-direct Voyage AI embeddings adapter (ADR-026) — the reference
  external implementation. Voyage is Anthropic's recommended embeddings
  partner; the Messages API used for generation (ADR-025) ships no
  embeddings endpoint.

  ## HTTP error classification (shared taxonomy, ADR-025)

  - `200` → `{:ok, [[float()]]}` (ordered by request index)
  - `429` → `{:error, :rate_limited}`
  - `5xx` → `{:error, :transient}`
  - `400` → `{:error, :permanent}` (caller bug — bad model/payload)
  - `401/403/404/413` → `{:error, :permanent}` (config/permission)
  - transport timeout → `{:error, :timeout}`
  - other transport error → `{:error, :transient}`

  ## Batching

  Voyage accepts ≤ 128 inputs per call; larger lists are chunked into
  sequential requests and concatenated. The first failing batch aborts
  the whole embed (callers treat the batch as atomic).

  ## Test injection

  Set `:ashy_walnut_desk, :voyage_req_options` (e.g. `plug: fun`) —
  mirrors `:anthropic_req_options` / `:twilio_req_options`.
  """

  @behaviour AshyWalnutDesk.Knowledge.Embedder

  require Logger

  @embeddings_url "https://api.voyageai.com/v1/embeddings"
  @max_batch 128

  @impl true
  def embed(texts, opts \\ []) when is_list(texts) do
    model = opts[:model] || default_model()

    with :ok <- validate_model(model) do
      texts
      |> Enum.chunk_every(@max_batch)
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
        case embed_batch(batch, model, opts) do
          {:ok, vectors} -> {:cont, {:ok, acc ++ vectors}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp embed_batch([], _model, _opts), do: {:ok, []}

  defp embed_batch(batch, model, opts) do
    body = %{
      model: model,
      input: batch,
      input_type: opts[:input_type] || "document"
    }

    case Req.post(@embeddings_url, build_req_options(body, opts)) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, extract_vectors(response)}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} when status >= 500 ->
        {:error, :transient}

      {:ok, %{status: status}} when status in 400..499 ->
        {:error, :permanent}

      {:error, %{__struct__: Req.TransportError, reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        Logger.warning("Embedders.Voyage: transport error #{reason_tag(reason)}")
        {:error, :transient}
    end
  end

  defp build_req_options(body, opts) do
    base = [
      headers: [{"authorization", "Bearer " <> api_key()}],
      json: body,
      receive_timeout: opts[:receive_timeout] || 30_000
    ]

    Keyword.merge(base, Application.get_env(:ashy_walnut_desk, :voyage_req_options, []))
  end

  defp extract_vectors(response) when is_map(response) do
    response
    |> Map.get("data", Map.get(response, :data, []))
    |> List.wrap()
    |> Enum.sort_by(fn item -> item["index"] || item[:index] || 0 end)
    |> Enum.map(fn item -> item["embedding"] || item[:embedding] || [] end)
  end

  defp validate_model(model) do
    allowed = Application.get_env(:ashy_walnut_desk, :embedding_model_allowlist, [])

    if model in allowed do
      :ok
    else
      {:error, {:model_not_allowed, model}}
    end
  end

  defp default_model do
    Application.get_env(:ashy_walnut_desk, :embedding_model, "voyage-3.5-lite")
  end

  defp api_key do
    voyage_config(:api_key) || System.get_env("VOYAGE_API_KEY") || fallback_key!()
  end

  defp voyage_config(key) do
    :ashy_walnut_desk
    |> Application.get_env(:voyage, [])
    |> Keyword.get(key)
  end

  # Mirrors Adapters.Anthropic.fallback_key!/0: unreachable in :prod
  # (config/runtime.exs raises at boot when EMBEDDING_ADAPTER=voyage
  # without VOYAGE_API_KEY); dev/test default to the Fixture embedder
  # and stub HTTP at the Req plug boundary.
  defp fallback_key! do
    case Application.fetch_env(:ashy_walnut_desk, :env) do
      {:ok, :prod} ->
        raise """
        Embedders.Voyage: missing VOYAGE_API_KEY.
        This branch should be unreachable in :prod — config/runtime.exs
        is supposed to raise at boot. Investigate config drift.
        """

      _ ->
        "DEV_PLACEHOLDER_VOYAGE_API_KEY"
    end
  end

  defp reason_tag(%{__struct__: mod}), do: inspect(mod)
  defp reason_tag(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_tag(reason) when is_binary(reason), do: reason
  defp reason_tag(_), do: "unknown"
end
