defmodule AshyWalnutDesk.Interaction.AuditChainConcurrencyTest do
  use AshyWalnutDesk.DataCase, async: false
  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Interaction.{Action, AuditChain, Channel, Conversation, Draft, Inbox}
  alias AshyWalnutDesk.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "parallel approvals and executes keep one continuous chain" do
    parent = self()
    n = 6
    %{operator: operator, inbox: inbox, drafts: drafts} = seed_chain_with_drafts(n)

    drafts
    |> Task.async_stream(
      fn draft ->
        Sandbox.allow(Repo, parent, self())

        {:ok, approved} =
          Ash.update(draft, %{compensation_body: "Comp"}, action: :approve, actor: operator)

        {:ok, _} =
          Ash.update(approved, %{approved_at: DateTime.add(DateTime.utc_now(), -6, :second)},
            action: :edit_draft,
            actor: operator
          )

        action =
          Action
          |> Ash.Query.for_read(:read, %{}, authorize?: false)
          |> Ash.Query.filter(expr(draft_id == ^approved.id))
          |> Ash.read_one!(authorize?: false)

        {:ok, _} = Ash.update(action, %{}, action: :execute, actor: operator)
        :ok
      end,
      max_concurrency: n,
      timeout: 30_000
    )
    |> Enum.each(fn {:ok, :ok} -> :ok end)

    assert {:ok, events} = AuditChain.walk(to_string(inbox.id))
    assert length(events) == 1 + 4 * n

    hashes = MapSet.new(Enum.map(events, & &1.hash))
    prev_hashes = events |> Enum.map(& &1.prev_hash) |> Enum.reject(&is_nil/1)

    assert length(prev_hashes) == length(Enum.uniq(prev_hashes))
    assert Enum.all?(prev_hashes, &MapSet.member?(hashes, &1))
  end

  defp seed_chain_with_drafts(n) do
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
            %{inbox_id: inbox.id, body: "Draft #{i}", status: :drafting},
            action: :compose_draft,
            actor: operator
          )

        draft
      end

    %{operator: operator, inbox: inbox, drafts: drafts}
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
