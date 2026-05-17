defmodule AshyWalnutDesk.Interaction.PolicyShapeTest do
  use AshyWalnutDesk.DataCase, async: true

  alias Ash.Policy.Info

  alias AshyWalnutDesk.Interaction.{
    Action,
    AuditEvent,
    Channel,
    Compensation,
    Conversation,
    Draft,
    Inbox,
    Message
  }

  @resources [
    Conversation,
    Message,
    Channel,
    Inbox,
    Draft,
    Action,
    Compensation,
    AuditEvent
  ]

  test "each interaction resource declares at least one policy" do
    Enum.each(@resources, fn resource ->
      assert Info.policies(resource) != [],
             "expected #{inspect(resource)} to declare at least one policy"
    end)
  end
end
