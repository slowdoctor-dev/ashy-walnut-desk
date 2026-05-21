defmodule AshyWalnutDesk.Knowledge do
  @moduledoc false

  use Ash.Domain,
    otp_app: :ashy_walnut_desk

  resources do
    resource(AshyWalnutDesk.Knowledge.Persona)
    resource(AshyWalnutDesk.Knowledge.Persona.Version)
  end
end
