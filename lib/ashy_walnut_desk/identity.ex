defmodule AshyWalnutDesk.Identity do
  @moduledoc false

  use Ash.Domain,
    otp_app: :ashy_walnut_desk

  resources do
    resource(AshyWalnutDesk.Identity.Identity)
    resource(AshyWalnutDesk.Identity.Identity.Version)
    resource(AshyWalnutDesk.Identity.Event)
    resource(AshyWalnutDesk.Identity.Event.Version)
    resource(AshyWalnutDesk.Identity.Appointment)
    resource(AshyWalnutDesk.Identity.Appointment.Version)
    resource(AshyWalnutDesk.Identity.Note)
    resource(AshyWalnutDesk.Identity.Note.Version)
  end
end
