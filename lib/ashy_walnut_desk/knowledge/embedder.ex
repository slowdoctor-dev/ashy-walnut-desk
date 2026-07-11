defmodule AshyWalnutDesk.Knowledge.Embedder do
  @moduledoc """
  Provider-agnostic embedding boundary for Knowledge-axis retrieval
  (ADR-026). Third instance of the adapter pattern (ADR-022 channel
  adapters, ADR-025 AI adapter).

  Implementations are pure functions over text batches; state (chunk
  rows, vectors) lives in resources, never in the adapter.
  """

  @type error_class :: :transient | :permanent | :rate_limited | :timeout | term()

  @callback embed(texts :: [String.t()], opts :: keyword()) ::
              {:ok, [[float()]]} | {:error, error_class()}

  @doc """
  Resolve the configured embedder against the allowlist.

  Returns `{:error, :not_configured}` when no adapter is set — the
  supported `EMBEDDING_ADAPTER=none` posture — so callers (Retriever,
  indexing worker) can skip the vector path instead of raising.
  """
  @spec resolve() ::
          {:ok, module()} | {:error, :not_configured | {:embedder_not_allowed, module()}}
  def resolve do
    module = Application.get_env(:ashy_walnut_desk, :embedding_adapter)
    allowlist = Application.get_env(:ashy_walnut_desk, :embedding_adapter_allowlist, [])

    cond do
      is_nil(module) -> {:error, :not_configured}
      module in allowlist -> {:ok, module}
      true -> {:error, {:embedder_not_allowed, module}}
    end
  end

  @doc "Configured vector dimension (must match the pgvector column)."
  @spec dimension() :: pos_integer()
  def dimension do
    Application.get_env(:ashy_walnut_desk, :embedding_dimension, 1024)
  end
end
