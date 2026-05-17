defmodule AshyWalnutDesk.Interaction.ChainSchemaTest do
  use AshyWalnutDesk.DataCase, async: true

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Interaction.{Action, AuditEvent, Compensation, Draft}

  test "action links uniquely to draft and references a channel" do
    action_relationships = relationship_names(Action)

    assert :draft in action_relationships
    assert :channel in action_relationships

    assert unique_index?(Action, [:draft_id])

    assert [:pending, :executed, :failed, :rolled_back] ==
             Info.attribute(Action, :status).constraints[:one_of]

    assert Draft == Info.relationship(Action, :draft).destination
  end

  test "compensation links uniquely to action and keeps sensitive body" do
    compensation_relationships = relationship_names(Compensation)

    assert :action in compensation_relationships
    assert unique_index?(Compensation, [:action_id])
    assert Info.attribute(Compensation, :body).sensitive?

    assert [:registered, :triggered, :completed, :failed] ==
             Info.attribute(Compensation, :status).constraints[:one_of]
  end

  test "audit_event models chain-topic polymorphic subject and actor link" do
    audit_relationships = relationship_names(AuditEvent)

    assert :actor in audit_relationships

    assert Ash.Type.UUID == Info.attribute(AuditEvent, :subject_id).type
    assert Ash.Type.Atom == Info.attribute(AuditEvent, :event_type).type
    assert Ash.Type.Atom == Info.attribute(AuditEvent, :subject_kind).type
  end

  defp relationship_names(resource) do
    resource |> Info.relationships() |> Enum.map(& &1.name)
  end

  defp unique_index?(resource, keys) do
    resource
    |> AshPostgres.DataLayer.Info.custom_indexes()
    |> Enum.any?(fn index -> index.fields == keys and index.unique end)
  end
end
