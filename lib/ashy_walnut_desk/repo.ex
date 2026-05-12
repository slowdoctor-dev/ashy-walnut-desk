defmodule AshyWalnutDesk.Repo do
  use AshPostgres.Repo,
    otp_app: :ashy_walnut_desk,
    adapter: Ecto.Adapters.Postgres,
    installed_extensions: ["pgvector", "pg_trgm", "citext"]
end
