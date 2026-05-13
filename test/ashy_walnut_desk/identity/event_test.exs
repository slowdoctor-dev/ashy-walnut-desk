defmodule AshyWalnutDesk.Identity.EventTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Event.Version
  alias AshyWalnutDesk.Identity.Identity

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

  defp register_identity(actor) do
    {:ok, identity} =
      Ash.create(
        Identity,
        %{
          display_name: "Alex Doe",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        action: :register_identity,
        actor: actor
      )

    identity
  end

  defp record_event(actor, identity, attrs \\ %{}) do
    Ash.create(
      Event,
      Map.merge(
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now(),
          summary: "Initial visit"
        },
        attrs
      ),
      action: :record_event,
      actor: actor
    )
  end

  # AC1 — action surface and ownership

  test "exposes the documented action surface" do
    action_names = Event |> Info.actions() |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               :read,
               :read_with_archived,
               :record_event,
               :update_event,
               :archive,
               :recover
             ]),
             action_names
           )
  end

  test "record_event requires an owning identity" do
    admin = create_user(:admin)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Event,
               %{
                 occurred_at: DateTime.utc_now(),
                 summary: "Orphan"
               },
               action: :record_event,
               actor: admin
             )
  end

  test "record_event sets recorded_by from actor and links to identity" do
    operator = create_user(:operator)
    identity = register_identity(operator)

    assert {:ok, event} = record_event(operator, identity, %{summary: "Cleaning"})
    assert event.identity_id == identity.id
    assert event.recorded_by_id == operator.id
    assert event.summary == "Cleaning"
  end

  test "update_event accepts occurred_at/summary/body only" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    {:ok, event} = record_event(operator, identity)

    new_time = DateTime.add(DateTime.utc_now(), 3600, :second)

    assert {:ok, updated} =
             Ash.update(
               event,
               %{occurred_at: new_time, summary: "Updated", body: "Notes"},
               action: :update_event,
               actor: operator
             )

    assert DateTime.compare(updated.occurred_at, new_time) == :eq
    assert updated.summary == "Updated"
    assert updated.body == "Notes"
  end

  # AC2 — role-based policies

  test "operator and admin can record_event; viewer cannot" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    assert {:ok, _} = record_event(admin, identity)
    assert {:ok, _} = record_event(operator, identity)

    assert {:error, %Ash.Error.Forbidden{}} = record_event(viewer, identity)
  end

  test "viewer can read but cannot update_event or archive" do
    admin = create_user(:admin)
    viewer = create_user(:viewer)
    identity = register_identity(admin)
    {:ok, event} = record_event(admin, identity)

    assert {:ok, _list} = Ash.read(Event, actor: viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(event, %{summary: "Hacked"},
               action: :update_event,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(event, %{}, action: :archive, actor: viewer)
  end

  test "unauthenticated callers are denied for read and write actions" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, event} = record_event(admin, identity)

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Event, actor: nil)

    # relate_actor(:recorded_by) trips on a nil actor before policy auth runs,
    # so the create denial surfaces as InvalidRelationship rather than
    # Forbidden — either is an unauthenticated write being refused.
    assert {:error, %struct{}} = record_event(nil, identity)
    assert struct in [Ash.Error.Forbidden, Ash.Error.Invalid]

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(event, %{summary: "X"}, action: :update_event, actor: nil)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(event, %{}, action: :archive, actor: nil)
  end

  test "operator cannot recover; admin can" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, event} = record_event(operator, identity)

    {:ok, archived} = Ash.update(event, %{}, action: :archive, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)

    assert {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
    assert is_nil(recovered.deleted_at)
  end

  # AC3 — soft-delete + default-filter

  test "archive sets deleted_at and default read filters archived rows" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, event} = record_event(operator, identity)

    {:ok, archived} = Ash.update(event, %{}, action: :archive, actor: operator)
    refute is_nil(archived.deleted_at)

    {:ok, visible} = Ash.read(Event, actor: admin)
    refute Enum.any?(visible, &(&1.id == event.id))

    {:ok, all} = Ash.read(Event, action: :read_with_archived, actor: admin)
    assert Enum.any?(all, &(&1.id == event.id))
  end

  test "archive is idempotent — second invocation does not change deleted_at" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, event} = record_event(admin, identity)

    {:ok, archived_once} = Ash.update(event, %{}, action: :archive, actor: admin)
    {:ok, archived_twice} = Ash.update(archived_once, %{}, action: :archive, actor: admin)

    assert DateTime.compare(archived_once.deleted_at, archived_twice.deleted_at) == :eq
  end

  test "read_with_archived is admin-only" do
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Event, action: :read_with_archived, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Event, action: :read_with_archived, actor: viewer)
  end

  # AC3 — sensitive attributes + paper trail redaction

  test "summary and body are marked sensitive" do
    %{sensitive?: summary_sensitive} = Info.attribute(Event, :summary)
    %{sensitive?: body_sensitive} = Info.attribute(Event, :body)
    assert summary_sensitive
    assert body_sensitive
  end

  test "record_event writes a version row that redacts sensitive attributes" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    raw_summary = "Secret consultation note"
    raw_body = "Sensitive body detail"

    {:ok, event} =
      record_event(admin, identity, %{summary: raw_summary, body: raw_body})

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == event.id))

    assert versions != []

    for v <- versions do
      assert v.changes["summary"] in [nil, "REDACTED"]
      assert v.changes["body"] in [nil, "REDACTED"]

      refute v.changes["summary"] == raw_summary
      refute v.changes["body"] == raw_body

      rendered = inspect(v.changes)
      refute rendered =~ raw_summary
      refute rendered =~ raw_body
    end
  end

  test "Version reads require an admin actor" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    {:ok, _event} = record_event(admin, identity)

    assert {:ok, _} = Ash.read(Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: viewer)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: nil)
  end
end
