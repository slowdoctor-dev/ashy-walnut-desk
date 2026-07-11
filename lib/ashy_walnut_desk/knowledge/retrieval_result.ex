defmodule AshyWalnutDesk.Knowledge.RetrievalResult do
  @moduledoc """
  Outcome of a retrieval attempt (story 5.4). `mode` records which
  rung of the ladder actually served: `:vector` (pgvector cosine),
  `:lexical` (pg_trgm fallback), or `:none` (retrieval disabled,
  nothing indexed, or nothing matched). Provenance-complete: each
  excerpt carries enough to resolve its source Manual version even
  after chunk rows are pruned.
  """

  @type excerpt :: %{
          manual_id: String.t(),
          manual_slug: String.t(),
          revision: pos_integer(),
          position: non_neg_integer(),
          content: String.t(),
          content_hash: String.t(),
          score: float() | nil,
          embedder: String.t() | nil
        }

  @type mode :: :vector | :lexical | :none

  @type t :: %__MODULE__{mode: mode(), excerpts: [excerpt()]}

  defstruct mode: :none, excerpts: []
end
