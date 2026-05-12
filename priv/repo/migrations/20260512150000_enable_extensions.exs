defmodule AshyWalnutDesk.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
  end

  def down do
    # down: intentional no-op
    # Dropping shared-cluster extensions can break other schemas/services.
    :ok
  end
end
