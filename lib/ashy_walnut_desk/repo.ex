defmodule AshyWalnutDesk.Repo do
  use Ecto.Repo,
    otp_app: :ashy_walnut_desk,
    adapter: Ecto.Adapters.Postgres
end
