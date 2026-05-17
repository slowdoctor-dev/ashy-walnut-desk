defmodule AshyWalnutDesk.Interaction.AuditRedactionTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
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

  test "sensitive interaction fields are marked sensitive" do
    assert Info.attribute(Conversation, :subject).sensitive?
    assert Info.attribute(Message, :body).sensitive?
    assert Info.attribute(Inbox, :summary).sensitive?
    assert Info.attribute(Draft, :body).sensitive?
    assert Info.attribute(Draft, :compensation_body).sensitive?
    assert Info.attribute(Draft, :ai_prompt).sensitive?
    assert Info.attribute(Draft, :ai_response).sensitive?
  end

  test "version resources are admin-only" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)

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
        %{subject: "secret-subject", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: admin
      )

    assert {:ok, _} = Ash.read(Conversation.Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Conversation.Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Conversation.Version, actor: viewer)

    versions =
      Conversation.Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == conversation.id))

    assert versions != []

    for v <- versions do
      assert v.changes["subject"] in [nil, "REDACTED"]
      refute inspect(v.changes) =~ "secret-subject"
    end
  end
end
