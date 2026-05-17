defmodule AshyWalnutDesk.Interaction.Properties.ChainInvariantsTest do
  use AshyWalnutDesk.DataCase, async: false
  use ExUnitProperties

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity

  alias AshyWalnutDesk.Interaction.{
    Action,
    AuditChain,
    Channel,
    Compensation,
    Conversation,
    Draft,
    Inbox
  }

  require Ash.Query

  @max_runs 20

  setup do
    %{admin: create_user(:admin)}
  end

  property "Action↔Compensation bijection", %{admin: admin} do
    check all(n <- integer(1..5), max_runs: @max_runs) do
      %{drafts: drafts} = seed_approved_chain(n, admin)

      Enum.each(drafts, fn draft ->
        {:ok, _} =
          Ash.update(draft, %{approved_at: DateTime.add(DateTime.utc_now(), -6, :second)},
            action: :edit_draft,
            actor: draft.approved_by
          )

        action =
          Action
          |> Ash.Query.filter(draft_id == ^draft.id)
          |> Ash.read_one!(authorize?: false)

        {:ok, _} = Ash.update(action, %{}, action: :execute, actor: draft.approved_by)
      end)

      action_ids =
        Action
        |> Ash.Query.filter(draft_id in ^Enum.map(drafts, & &1.id))
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      compensations =
        Compensation
        |> Ash.Query.filter(action_id in ^action_ids)
        |> Ash.read!(authorize?: false)

      compensation_action_ids = Enum.map(compensations, & &1.action_id)

      assert length(action_ids) == n
      assert length(compensations) == n
      assert MapSet.new(action_ids) == MapSet.new(compensation_action_ids)
    end
  end

  property "payload canonicalization deterministic" do
    check all(
            event_type <-
              member_of([
                :inbox_opened,
                :draft_started,
                :draft_approved,
                :action_executed,
                :compensation_registered
              ]),
            payload <- payload_generator(),
            max_runs: @max_runs
          ) do
      payload = Map.take(payload, allowed_keys(event_type))

      assert {:ok, canonical_a} = AuditChain.canonicalize_payload(event_type, payload)
      assert {:ok, canonical_b} = AuditChain.canonicalize_payload(event_type, payload)
      assert canonical_a == canonical_b
    end
  end

  defp seed_approved_chain(n, admin) do
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
        %{
          conversation_id: conversation.id,
          status: :drafting,
          summary: "Need response",
          recorded_by_id: operator.id
        },
        action: :record_inbox,
        actor: operator
      )

    drafts =
      for i <- 1..n do
        {:ok, draft} =
          Ash.create(
            Draft,
            %{
              inbox_id: inbox.id,
              body: "Draft #{i}",
              compensation_body: "Comp #{i}",
              status: :drafting
            },
            action: :compose_draft,
            actor: operator
          )

        {:ok, approved} = Ash.update(draft, %{}, action: :approve, actor: operator)
        Ash.load!(approved, [:approved_by], authorize?: false)
      end

    %{drafts: drafts}
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

  defp payload_generator do
    fixed_map(%{
      inbox_id: string(:alphanumeric, min_length: 4, max_length: 16),
      conversation_id: string(:alphanumeric, min_length: 4, max_length: 16),
      identity_id: string(:alphanumeric, min_length: 4, max_length: 16),
      draft_id: string(:alphanumeric, min_length: 4, max_length: 16),
      approved_at: map(integer(1..2_000_000_000), &DateTime.from_unix!(&1, :second)),
      approved_by_id: string(:alphanumeric, min_length: 4, max_length: 16),
      action_id: string(:alphanumeric, min_length: 4, max_length: 16),
      channel_id: string(:alphanumeric, min_length: 4, max_length: 16),
      outcome: one_of([constant(:ok), constant(:failed), constant("ok")]),
      compensation_id: string(:alphanumeric, min_length: 4, max_length: 16)
    })
  end

  defp allowed_keys(:inbox_opened), do: [:inbox_id, :conversation_id, :identity_id]
  defp allowed_keys(:draft_started), do: [:inbox_id, :draft_id]
  defp allowed_keys(:draft_approved), do: [:draft_id, :approved_at, :approved_by_id]
  defp allowed_keys(:action_executed), do: [:action_id, :draft_id, :channel_id, :outcome]
  defp allowed_keys(:compensation_registered), do: [:compensation_id, :action_id]
end
