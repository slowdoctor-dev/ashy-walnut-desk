defmodule AshyWalnutDesk.Repo do
  use AshPostgres.Repo,
    otp_app: :ashy_walnut_desk,
    adapter: Ecto.Adapters.Postgres

  def installed_extensions do
    ["pgvector", "pg_trgm", "citext"]
  end

  def min_pg_version do
    %Version{major: 16, minor: 0, patch: 0}
  end
end
