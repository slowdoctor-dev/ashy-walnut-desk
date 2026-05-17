defmodule AshyWalnutDesk.Interaction.ConversationTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation}

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

  defp create_identity(actor, attrs \\ %{}) do
    Ash.create(
      Identity,
      Map.merge(
        %{
          display_name: "Identity #{System.unique_integer([:positive])}",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        attrs
      ),
      action: :register_identity,
      actor: actor
    )
  end

  defp create_channel(actor, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    Ash.create(
      Channel,
      Map.merge(
        %{
          slug: "stub-#{unique}",
          display_name: "Stub #{unique}",
          adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
        },
        attrs
      ),
      action: :register_channel,
      actor: actor
    )
  end

  test "rejects open_conversation when identity is archived" do
    admin = create_user(:admin)
    operator = create_user(:operator)

    {:ok, identity} = create_identity(admin)
    {:ok, archived_identity} = Ash.update(identity, %{}, action: :archive, actor: admin)
    {:ok, channel} = create_channel(admin)

    subject = "Need follow up"

    assert {:error, error} =
             Ash.create(
               Conversation,
               %{
                 subject: subject,
                 identity_id: archived_identity.id,
                 channel_id: channel.id
               },
               action: :open_conversation,
               actor: operator
             )

    assert Exception.message(error) =~ "cannot reference archived identity"

    persisted =
      Conversation
      |> Ash.read!(action: :read_with_archived, authorize?: false)
      |> Enum.filter(&(&1.identity_id == archived_identity.id and &1.subject == subject))

    assert persisted == []
  end
end
