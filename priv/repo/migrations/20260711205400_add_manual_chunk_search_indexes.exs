defmodule AshyWalnutDesk.Repo.Migrations.AddManualChunkSearchIndexes do
  @moduledoc """
  Hand-authored (story 5.3 AC5): pgvector HNSW + pg_trgm GIN indexes on
  manual_chunks. ash_postgres has no DSL for pgvector index types, so
  these live outside the generated migration / snapshots — the codegen
  never sees or regenerates them (same pattern as the Phase 0
  enable-extensions migrations).
  """

  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX manual_chunks_embedding_hnsw_idx
    ON manual_chunks USING hnsw (embedding vector_cosine_ops)
    """)

    execute("""
    CREATE INDEX manual_chunks_content_trgm_idx
    ON manual_chunks USING gin (content gin_trgm_ops)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS manual_chunks_embedding_hnsw_idx")
    execute("DROP INDEX IF EXISTS manual_chunks_content_trgm_idx")
  end
end
