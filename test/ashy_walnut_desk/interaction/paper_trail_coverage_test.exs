defmodule AshyWalnutDesk.Interaction.PaperTrailCoverageTest do
  use AshyWalnutDesk.DataCase, async: false

  require Ash.Query

  alias AshyWalnutDesk.Accounts.{SystemActor, User}
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Channel, Conversation, Draft, Inbox, Message}

  test "mutable interaction resources write version rows for create/update with redacted sensitive fields" do
    admin = create_user(:admin)

    {:ok, identity} = create_identity(admin)
    {:ok, channel} = create_channel(admin)
    {:ok, conversation} = create_conversation(admin, identity, channel)

    # ADR-024: inbound rows require the webhook intake path.
    system_actor = SystemActor.ensure!()

    {:ok, message} =
      Ash.create(
        Message,
        %{conversation_id: conversation.id, direction: :inbound, body: "sensitive-body"},
        action: :record_message,
        actor: system_actor,
        authorize?: false,
        context: %{from_inbound_webhook: true}
      )

    {:ok, _archived_message} = Ash.update(message, %{}, action: :archive, actor: admin)

    assert_version_count_at_least(Message.Version, message.id, 2)
    assert_changes_redacted(Message.Version, message.id, "body")

    {:ok, _disabled_channel} = Ash.update(channel, %{}, action: :disable, actor: admin)
    assert_version_count_at_least(Channel.Version, channel.id, 2)

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "sensitive-summary"},
        action: :record_inbox,
        actor: admin
      )

    {:ok, _updated_inbox} =
      Ash.update(
        inbox,
        %{summary: "new-sensitive-summary"},
        action: :edit_summary,
        actor: admin
      )

    assert_version_count_at_least(Inbox.Version, inbox.id, 2)
    assert_changes_redacted(Inbox.Version, inbox.id, "summary")

    {:ok, draft} =
      Ash.create(
        Draft,
        %{
          inbox_id: inbox.id,
          body: "draft-sensitive-body",
          compensation_body: "draft-sensitive-compensation",
          status: :drafting
        },
        action: :compose_draft,
        actor: admin
      )

    {:ok, _updated_draft} =
      Ash.update(
        draft,
        %{body: "edited-sensitive-body", compensation_body: "edited-sensitive-compensation"},
        action: :revise,
        actor: admin
      )

    assert_version_count_at_least(Draft.Version, draft.id, 2)
    assert_changes_redacted(Draft.Version, draft.id, "body")
    assert_changes_redacted(Draft.Version, draft.id, "compensation_body")

    {:ok, _archived_conversation} = Ash.update(conversation, %{}, action: :archive, actor: admin)
    assert_version_count_at_least(Conversation.Version, conversation.id, 2)
    assert_changes_redacted(Conversation.Version, conversation.id, "subject")
  end

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

  defp create_identity(actor) do
    Ash.create(
      Identity,
      %{
        display_name: "Identity #{System.unique_integer([:positive])}",
        primary_identifier: "+1555#{System.unique_integer([:positive])}"
      },
      action: :register_identity,
      actor: actor
    )
  end

  defp create_channel(actor) do
    unique = System.unique_integer([:positive])

    Ash.create(
      Channel,
      %{
        slug: "stub-#{unique}",
        display_name: "Stub #{unique}",
        adapter_module: "AshyWalnutDesk.Interaction.Adapters.Stub"
      },
      action: :register_channel,
      actor: actor
    )
  end

  defp create_conversation(actor, identity, channel) do
    Ash.create(
      Conversation,
      %{subject: "sensitive-subject", identity_id: identity.id, channel_id: channel.id},
      action: :open_conversation,
      actor: actor
    )
  end

  defp assert_version_count_at_least(version_resource, source_id, expected_count) do
    versions = version_rows_for(version_resource, source_id)
    assert length(versions) >= expected_count
  end

  defp assert_changes_redacted(version_resource, source_id, field) do
    versions = version_rows_for(version_resource, source_id)

    assert Enum.any?(versions, fn version ->
             Map.get(version.changes || %{}, field) == "REDACTED"
           end),
           "#{inspect(version_resource)} missing redacted #{field} for source #{source_id}"
  end

  defp version_rows_for(version_resource, source_id) do
    version_resource
    |> Ash.Query.filter(version_source_id: source_id)
    |> Ash.read!(action: :read, authorize?: false)
  end
end
