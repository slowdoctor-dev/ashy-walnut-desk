defmodule AshyWalnutDesk.Interaction.SoftDeleteTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.Message
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  test "conversation/message/inbox/draft follow archive-read_with_archived-recover flow" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel, subject: "subject")

    {:ok, message} =
      Ash.create(
        Message,
        %{conversation_id: conversation.id, direction: :inbound, body: "inbound"},
        action: :record_message,
        actor: operator
      )

    inbox = Fixtures.seed_inbox(operator, conversation, summary: "summary")
    draft = Fixtures.seed_draft(operator, inbox, body: "draft", compensation_body: nil)

    records = %{conversation: conversation, message: message, inbox: inbox, draft: draft}

    Enum.each(records, fn {resource_name, record} ->
      {:ok, archived} = Ash.update(record, %{}, action: :archive, actor: operator)
      refute is_nil(archived.deleted_at)

      {:ok, visible} = Ash.read(record.__struct__, actor: admin)
      refute Enum.any?(visible, &(&1.id == record.id))

      {:ok, all_rows} = Ash.read(record.__struct__, action: :read_with_archived, actor: admin)

      assert Enum.any?(all_rows, &(&1.id == record.id)),
             "missing #{resource_name} in read_with_archived"

      assert {:error, %Ash.Error.Forbidden{}} =
               Ash.update(archived, %{}, action: :recover, actor: operator)

      assert {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
      assert is_nil(recovered.deleted_at)
    end)
  end
end
