defmodule AshyWalnutDesk.Repo.Migrations.AddAuditEventChainIndexes do
  use Ecto.Migration

  def up do
    execute(
      "CREATE INDEX audit_events_chain_topic_inserted_at_idx ON audit_events (chain_topic, inserted_at)"
    )

    execute("CREATE INDEX audit_events_prev_hash_idx ON audit_events (prev_hash)")
  end

  def down do
    execute("DROP INDEX IF EXISTS audit_events_prev_hash_idx")
    execute("DROP INDEX IF EXISTS audit_events_chain_topic_inserted_at_idx")
  end
end
