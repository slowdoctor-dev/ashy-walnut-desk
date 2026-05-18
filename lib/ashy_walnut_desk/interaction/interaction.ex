defmodule AshyWalnutDesk.Interaction do
  @moduledoc false

  use Ash.Domain,
    otp_app: :ashy_walnut_desk

  resources do
    resource(AshyWalnutDesk.Interaction.Conversation)
    resource(AshyWalnutDesk.Interaction.Conversation.Version)
    resource(AshyWalnutDesk.Interaction.Message)
    resource(AshyWalnutDesk.Interaction.Message.Version)
    resource(AshyWalnutDesk.Interaction.Channel)
    resource(AshyWalnutDesk.Interaction.Channel.Version)
    resource(AshyWalnutDesk.Interaction.Inbox)
    resource(AshyWalnutDesk.Interaction.Inbox.Version)
    resource(AshyWalnutDesk.Interaction.Draft)
    resource(AshyWalnutDesk.Interaction.Draft.Version)
    resource(AshyWalnutDesk.Interaction.Action)
    resource(AshyWalnutDesk.Interaction.Compensation)
    resource(AshyWalnutDesk.Interaction.AuditEvent)
    resource(AshyWalnutDesk.Interaction.InboundDelivery)
  end
end
