defmodule AshyWalnutDesk.Interaction.DraftApprovalConcurrencyTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, Channel, Compensation, Conversation, Draft, Inbox}

  test "concurrent approve serializes and only one wins" do
    %{operator: operator, draft: draft} = seed_chain()

    results =
      1..4
      |> Task.async_stream(
        fn _ ->
          Ash.update(draft, %{compensation_body: "Compensate"}, action: :approve, actor: operator)
        end,
        max_concurrency: 4,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))

    draft_error_count =
      Enum.count(results, fn
        {:error, error} -> Exception.message(error) =~ "draft_not_drafting"
        _ -> false
      end)

    assert success_count == 1
    assert draft_error_count == 3

    assert length(Ash.read!(Action, authorize?: false)) == 1
    assert length(Ash.read!(Compensation, authorize?: false)) == 1
  end

  defp seed_chain do
    admin = create_user(:admin)
    operator = create_user(:operator)
    unique = System.unique_integer([:positive])

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "Identity #{unique}", primary_identifier: "+1555#{unique}"},
        action: :register_identity,
        actor: admin
      )

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
        %{subject: "Thread", identity_id: identity.id, channel_id: channel.id},
        action: :open_conversation,
        actor: operator
      )

    {:ok, inbox} =
      Ash.create(
        Inbox,
        %{conversation_id: conversation.id, summary: "Need response"},
        action: :record_inbox,
        actor: operator
      )

    {:ok, draft} =
      Ash.create(
        Draft,
        %{inbox_id: inbox.id, body: "Draft body", status: :drafting},
        action: :compose_draft,
        actor: operator
      )

    %{operator: operator, draft: draft}
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
end
