defmodule AshyWalnutDesk.Interaction.SoftDeleteTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Draft, Inbox, Message}

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{email: "#{role}-#{System.unique_integer([:positive])}@example.com", role: role},
        action: :register,
        authorize?: false
      )

    user
  end

  defp create_baseline(admin, operator) do
    {:ok, identity} =
      Ash.create(
        Identity,
        %{
          display_name: "Identity #{System.unique_integer([:positive])}",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        action: :register_identity,
        actor: admin
      )

    unique = System.unique_integer([:positive])

    {:ok, channel} =
      Ash.create(
        Channel,
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        action: :register_channel,
        actor: admin
      )

    {:ok, conversation} =
      Ash.create(
        Conversation,
        %{subject: "subject", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    {:ok, message} =
      Ash.create(
        Message,
        %{conversation_id: conversation.id, direction: :inbound, body: "inbound"},
        action: :record_message,
        actor: operator
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "summary"},
        action: :record_inbox,
        actor: operator
      )

    {:ok, draft} =
      Ash.create(
        Draft,
        %{inbox_id: inbox.id, body: "draft", status: :drafting},
        action: :compose_draft,
        actor: operator
      )

    %{conversation: conversation, message: message, inbox: inbox, draft: draft}
  end

  test "conversation/message/inbox/draft follow archive-read_with_archived-recover flow" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    records = create_baseline(admin, operator)

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
