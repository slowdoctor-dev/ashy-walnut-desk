defmodule AshyWalnutDesk.Identity.SensitiveFieldVisibilityTest do
  use AshyWalnutDesk.DataCase, async: false

  alias AshyWalnutDesk.AccountsFixtures
  alias AshyWalnutDesk.Identity.{Appointment, Event, Identity, Note}

  defp seed_identity(admin) do
    unique = System.unique_integer([:positive])

    {:ok, identity} =
      Ash.create(
        Identity,
        %{display_name: "Sensitive Visibility", primary_identifier: "+1555#{unique}"},
        action: :register_identity,
        actor: admin
      )

    identity
  end

  test "viewer cannot read Event.summary/body, Appointment.summary, or Note.body" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    viewer = AccountsFixtures.create_user(:viewer)
    identity = seed_identity(admin)

    {:ok, event} =
      Ash.create(
        Event,
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now(),
          summary: "Event s",
          body: "Event b"
        },
        action: :record_event,
        actor: operator
      )

    {:ok, appointment} =
      Ash.create(
        Appointment,
        %{
          identity_id: identity.id,
          scheduled_for: DateTime.add(DateTime.utc_now(), 3600, :second),
          appointment_type: :initial,
          summary: "Appt s"
        },
        action: :schedule_appointment,
        actor: operator
      )

    {:ok, note} =
      Ash.create(
        Note,
        %{identity_id: identity.id, body: "Note body"},
        action: :record_note,
        actor: operator
      )

    {:ok, viewer_event} = Ash.get(Event, event.id, actor: viewer)
    {:ok, viewer_appointment} = Ash.get(Appointment, appointment.id, actor: viewer)
    {:ok, viewer_note} = Ash.get(Note, note.id, actor: viewer)

    assert match?(%Ash.ForbiddenField{}, viewer_event.summary)
    assert match?(%Ash.ForbiddenField{}, viewer_event.body)
    assert match?(%Ash.ForbiddenField{}, viewer_appointment.summary)
    assert match?(%Ash.ForbiddenField{}, viewer_note.body)
  end

  test "operator retains read access to those same fields" do
    admin = AccountsFixtures.create_user(:admin)
    operator = AccountsFixtures.create_user(:operator)
    identity = seed_identity(admin)

    {:ok, event} =
      Ash.create(
        Event,
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now(),
          summary: "Event s",
          body: "Event b"
        },
        action: :record_event,
        actor: operator
      )

    {:ok, appointment} =
      Ash.create(
        Appointment,
        %{
          identity_id: identity.id,
          scheduled_for: DateTime.add(DateTime.utc_now(), 3600, :second),
          appointment_type: :initial,
          summary: "Appt s"
        },
        action: :schedule_appointment,
        actor: operator
      )

    {:ok, note} =
      Ash.create(
        Note,
        %{identity_id: identity.id, body: "Note body"},
        action: :record_note,
        actor: operator
      )

    {:ok, operator_event} = Ash.get(Event, event.id, actor: operator)
    {:ok, operator_appointment} = Ash.get(Appointment, appointment.id, actor: operator)
    {:ok, operator_note} = Ash.get(Note, note.id, actor: operator)

    assert operator_event.summary == "Event s"
    assert operator_event.body == "Event b"
    assert operator_appointment.summary == "Appt s"
    assert operator_note.body == "Note body"
  end
end
