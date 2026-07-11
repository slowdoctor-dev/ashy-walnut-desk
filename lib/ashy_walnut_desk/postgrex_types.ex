# Registers the pgvector `vector` type with Postgrex (story 5.3/5.4).
# Per AshPostgres.Extensions.Vector docs this is a bare call, not a
# module; the repo points at it via `types:` in config/config.exs.
Postgrex.Types.define(
  AshyWalnutDesk.PostgrexTypes,
  [AshPostgres.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
