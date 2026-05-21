defmodule AshyWalnutDesk.Interaction.DraftApprovalSupersedeSiblingsTest do
  use AshyWalnutDesk.DataCase, async: false

  import Ash.Expr
  require Ash.Query

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Interaction.{AuditEvent, Draft}
  alias AshyWalnutDesk.InteractionFixtures, as: Fixtures

  setup do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = Fixtures.seed_identity(admin)
    channel = Fixtures.seed_channel(admin)
    conversation = Fixtures.seed_conversation(operator, identity, channel)
    inbox = Fixtures.seed_inbox(operator, conversation)

    %{admin: admin, operator: operator, inbox: inbox}
  end

  test "approve supersedes all other drafting siblings and stamps chain events", %{
    admin: admin,
    operator: operator,
    inbox: inbox
  } do
    winner =
      Fixtures.seed_draft(operator, inbox,
        body: "Winner",
        ai_validator_output: %{"passed?" => true}
      )

    loser_a = Fixtures.seed_draft(operator, inbox, body: "Loser A")
    loser_b = Fixtures.seed_draft(operator, inbox, body: "Loser B")

    assert {:ok, approved} = Ash.update(winner, %{}, action: :approve, actor: operator)
    assert approved.status == :approved

    all_drafts =
      Draft
      |> Ash.Query.for_read(:read_with_archived, %{}, actor: admin)
      |> Ash.Query.filter(expr(inbox_id == ^inbox.id))
      |> Ash.Query.sort(created_at: :asc)
      |> Ash.read!(actor: admin)

    statuses = Map.new(all_drafts, &{&1.id, &1.status})
    assert statuses[winner.id] == :approved
    assert statuses[loser_a.id] == :superseded
    assert statuses[loser_b.id] == :superseded

    superseded_events =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, actor: admin)
      |> Ash.Query.filter(
        expr(event_type == :draft_superseded and chain_topic == ^to_string(inbox.id))
      )
      |> Ash.read!(actor: admin)

    assert length(superseded_events) == 2

    approved_event =
      AuditEvent
      |> Ash.Query.for_read(:read, %{}, actor: admin)
      |> Ash.Query.filter(expr(event_type == :draft_approved and subject_id == ^winner.id))
      |> Ash.read_one!(actor: admin)

    assert MapSet.new(approved_event.payload["superseded_sibling_draft_ids"]) ==
             MapSet.new([loser_a.id, loser_b.id])
  end
end
