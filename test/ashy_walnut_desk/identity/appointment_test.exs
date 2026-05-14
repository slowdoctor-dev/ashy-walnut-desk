defmodule AshyWalnutDesk.Identity.AppointmentTest do
  use AshyWalnutDesk.DataCase, async: false

  alias Ash.Resource.Info
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Appointment.Version
  alias AshyWalnutDesk.Identity.Event
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

  defp record_event(actor, identity) do
    {:ok, event} =
      Ash.create(
        Event,
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now(),
          summary: "Initial visit"
        },
        action: :record_event,
        actor: actor
      )

    event
  end

  defp schedule_appointment(actor, identity, attrs \\ %{}) do
    Ash.create(
      Appointment,
      Map.merge(
        %{
          identity_id: identity.id,
          scheduled_for: DateTime.add(DateTime.utc_now(), 3600, :second),
          summary: "Check-up"
        },
        attrs
      ),
      action: :schedule_appointment,
      actor: actor
    )
  end

  # AC1 — action surface, ownership link, status transitions

  test "exposes the documented action surface" do
    action_names = Appointment |> Info.actions() |> Enum.map(& &1.name) |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new([
               :read,
               :read_with_archived,
               :schedule_appointment,
               :reschedule,
               :cancel,
               :complete,
               :archive,
               :recover
             ]),
             action_names
           )
  end

  test "schedule_appointment requires an owning identity" do
    admin = create_user(:admin)

    assert {:error, %Ash.Error.Invalid{}} =
             Ash.create(
               Appointment,
               %{
                 scheduled_for: DateTime.utc_now(),
                 summary: "Orphan"
               },
               action: :schedule_appointment,
               actor: admin
             )
  end

  test "schedule_appointment defaults type to :initial and status to :scheduled" do
    operator = create_user(:operator)
    identity = register_identity(operator)

    assert {:ok, appointment} = schedule_appointment(operator, identity)
    assert appointment.appointment_type == :initial
    assert appointment.status == :scheduled
    assert appointment.identity_id == identity.id
    assert appointment.recorded_by_id == operator.id
    assert is_nil(appointment.originating_event_id)
  end

  test "reschedule updates scheduled_for only" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    {:ok, appointment} = schedule_appointment(operator, identity)

    new_time = DateTime.add(DateTime.utc_now(), 7200, :second)

    assert {:ok, rescheduled} =
             Ash.update(appointment, %{scheduled_for: new_time},
               action: :reschedule,
               actor: operator
             )

    assert DateTime.compare(rescheduled.scheduled_for, new_time) == :eq
    assert rescheduled.status == :scheduled
  end

  test "cancel transitions status to :cancelled" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    {:ok, appointment} = schedule_appointment(operator, identity)

    assert {:ok, cancelled} =
             Ash.update(appointment, %{}, action: :cancel, actor: operator)

    assert cancelled.status == :cancelled
  end

  test "complete transitions status to :completed" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    {:ok, appointment} = schedule_appointment(operator, identity)

    assert {:ok, completed} =
             Ash.update(appointment, %{}, action: :complete, actor: operator)

    assert completed.status == :completed
  end

  # AC2 — originating_event_id contract

  test "follow_up requires originating_event_id" do
    operator = create_user(:operator)
    identity = register_identity(operator)

    assert {:error, %Ash.Error.Invalid{} = err} =
             schedule_appointment(operator, identity, %{appointment_type: :follow_up})

    rendered = Exception.message(err)
    assert rendered =~ "originating_event_id"
  end

  test "follow_up with originating_event_id succeeds" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    event = record_event(operator, identity)

    assert {:ok, appointment} =
             schedule_appointment(operator, identity, %{
               appointment_type: :follow_up,
               originating_event_id: event.id
             })

    assert appointment.appointment_type == :follow_up
    assert appointment.originating_event_id == event.id
  end

  test "initial with originating_event_id is rejected" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    event = record_event(operator, identity)

    assert {:error, %Ash.Error.Invalid{} = err} =
             schedule_appointment(operator, identity, %{
               appointment_type: :initial,
               originating_event_id: event.id
             })

    rendered = Exception.message(err)
    assert rendered =~ "originating_event_id"
  end

  test "recurring with originating_event_id is rejected" do
    operator = create_user(:operator)
    identity = register_identity(operator)
    event = record_event(operator, identity)

    assert {:error, %Ash.Error.Invalid{}} =
             schedule_appointment(operator, identity, %{
               appointment_type: :recurring,
               originating_event_id: event.id
             })
  end

  test "follow_up rejects originating_event_id from a different identity" do
    operator = create_user(:operator)
    own_identity = register_identity(operator)
    other_identity = register_identity(operator)
    foreign_event = record_event(operator, other_identity)

    assert {:error, %Ash.Error.Invalid{} = err} =
             schedule_appointment(operator, own_identity, %{
               appointment_type: :follow_up,
               originating_event_id: foreign_event.id
             })

    assert Exception.message(err) =~ "same identity"
  end

  test "follow_up rejects originating_event_id from a soft-deleted foreign event" do
    operator = create_user(:operator)
    admin = create_user(:admin)
    own_identity = register_identity(operator)
    other_identity = register_identity(operator)
    foreign_event = record_event(operator, other_identity)

    {:ok, _archived} = Ash.update(foreign_event, %{}, action: :archive, actor: admin)

    assert {:error, %Ash.Error.Invalid{} = err} =
             schedule_appointment(operator, own_identity, %{
               appointment_type: :follow_up,
               originating_event_id: foreign_event.id
             })

    assert Exception.message(err) =~ "same identity"
  end

  # AC3 — role-based policies + viewer + unauthenticated denial

  test "operator and admin can schedule; viewer cannot" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    assert {:ok, _} = schedule_appointment(admin, identity)
    assert {:ok, _} = schedule_appointment(operator, identity)
    assert {:error, %Ash.Error.Forbidden{}} = schedule_appointment(viewer, identity)
  end

  test "viewer can read but cannot reschedule/cancel/complete/archive" do
    admin = create_user(:admin)
    viewer = create_user(:viewer)
    identity = register_identity(admin)
    {:ok, appointment} = schedule_appointment(admin, identity)

    assert {:ok, _list} = Ash.read(Appointment, actor: viewer)

    new_time = DateTime.add(DateTime.utc_now(), 7200, :second)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{scheduled_for: new_time},
               action: :reschedule,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{}, action: :cancel, actor: viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{}, action: :complete, actor: viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{}, action: :archive, actor: viewer)
  end

  test "unauthenticated callers are denied for read and write actions" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, appointment} = schedule_appointment(admin, identity)

    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Appointment, actor: nil)

    # relate_actor(:recorded_by) on a nil actor surfaces as InvalidRelationship
    # rather than Forbidden — either is an unauthenticated write being refused.
    assert {:error, %struct{}} = schedule_appointment(nil, identity)
    assert struct in [Ash.Error.Forbidden, Ash.Error.Invalid]

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{}, action: :cancel, actor: nil)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(appointment, %{}, action: :archive, actor: nil)
  end

  test "operator cannot recover; admin can" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, appointment} = schedule_appointment(operator, identity)

    {:ok, archived} = Ash.update(appointment, %{}, action: :archive, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)

    assert {:ok, recovered} = Ash.update(archived, %{}, action: :recover, actor: admin)
    assert is_nil(recovered.deleted_at)
  end

  # AC4 — soft-delete + paper trail redaction + admin-only Version reads

  test "archive sets deleted_at and default read filters archived rows" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    identity = register_identity(admin)
    {:ok, appointment} = schedule_appointment(operator, identity)

    {:ok, archived} = Ash.update(appointment, %{}, action: :archive, actor: operator)
    refute is_nil(archived.deleted_at)

    {:ok, visible} = Ash.read(Appointment, actor: admin)
    refute Enum.any?(visible, &(&1.id == appointment.id))

    {:ok, all} = Ash.read(Appointment, action: :read_with_archived, actor: admin)
    assert Enum.any?(all, &(&1.id == appointment.id))
  end

  test "archive is idempotent — second invocation does not change deleted_at" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    {:ok, appointment} = schedule_appointment(admin, identity)

    {:ok, archived_once} = Ash.update(appointment, %{}, action: :archive, actor: admin)
    {:ok, archived_twice} = Ash.update(archived_once, %{}, action: :archive, actor: admin)

    assert DateTime.compare(archived_once.deleted_at, archived_twice.deleted_at) == :eq
  end

  test "read_with_archived is admin-only" do
    operator = create_user(:operator)
    viewer = create_user(:viewer)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Appointment, action: :read_with_archived, actor: operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.read(Appointment, action: :read_with_archived, actor: viewer)
  end

  test "summary is marked sensitive" do
    %{sensitive?: summary_sensitive} = Info.attribute(Appointment, :summary)
    assert summary_sensitive
  end

  test "schedule_appointment writes a version row that redacts sensitive attributes" do
    admin = create_user(:admin)
    identity = register_identity(admin)
    raw_summary = "Confidential follow-up topic"

    {:ok, appointment} = schedule_appointment(admin, identity, %{summary: raw_summary})

    versions =
      Version
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.version_source_id == appointment.id))

    assert versions != []

    for v <- versions do
      assert v.changes["summary"] in [nil, "REDACTED"]
      refute v.changes["summary"] == raw_summary

      rendered = inspect(v.changes)
      refute rendered =~ raw_summary
    end
  end

  test "Version reads require an admin actor" do
    admin = create_user(:admin)
    operator = create_user(:operator)
    viewer = create_user(:viewer)
    identity = register_identity(admin)

    {:ok, _appointment} = schedule_appointment(admin, identity)

    assert {:ok, _} = Ash.read(Version, actor: admin)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: operator)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: viewer)
    assert {:error, %Ash.Error.Forbidden{}} = Ash.read(Version, actor: nil)
  end
end
