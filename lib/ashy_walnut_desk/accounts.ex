defmodule AshyWalnutDesk.Accounts do
  @moduledoc false

  use Ash.Domain,
    otp_app: :ashy_walnut_desk

  resources do
    resource(AshyWalnutDesk.Accounts.User)
    resource(AshyWalnutDesk.Accounts.User.Version)
    resource(AshyWalnutDesk.Accounts.Token)
  end
end
