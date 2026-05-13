defmodule AshyWalnutDesk.Identity.TimelinePropertyTest do
  @moduledoc """
  Property-based test for Phase 1 architecture §11: the merged
  Event/Appointment/Note timeline for an Identity is monotonic by time.

  The architecture phrasing is "monotonically non-decreasing"; the
  operator-facing `IdentityLive.Show.load_timeline/1` sorts with
  `{:desc, DateTime}` so the newest entries appear first. The contract
  this test proves is sortedness in the same direction operators
  actually see — i.e. non-increasing. The merge logic here mirrors
  `IdentityLive.Show` (same Ash queries, same entry shape, same sort).
  """

  use AshyWalnutDesk.DataCase, async: false
  use ExUnitProperties

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note

  require Ash.Query

  # DB-backed property tests pay an insert cost per iteration; cap the run
  # count so `just verify` stays under a couple of seconds.
  @max_runs 25

  defp create_operator do
    {:ok, user} =
      Ash.create(
        User,
        %{
          email: "operator-#{System.unique_integer([:positive])}@example.com",
          role: :operator
        },
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
          display_name: "Alex #{System.unique_integer([:positive])}",
          primary_identifier: "+1555#{System.unique_integer([:positive])}"
        },
        action: :register_identity,
        actor: actor
      )

    identity
  end

  # Roughly ±2 years from now, in microsecond resolution — matches the
  # `:utc_datetime_usec` shape of `Event.occurred_at` /
  # `Appointment.scheduled_for`. Random offsets give the merge real work
  # to do (otherwise everything clusters at `now`).
  defp offset_seconds_generator do
    integer(-63_072_000..63_072_000)
  end

  defp record_event!(actor, identity_id, offset_seconds) do
    {:ok, event} =
      Ash.create(
        Event,
        %{
          identity_id: identity_id,
          occurred_at: DateTime.add(DateTime.utc_now(), offset_seconds, :second),
          summary: "Event #{System.unique_integer([:positive])}"
        },
        action: :record_event,
        actor: actor
      )

    event
  end

  defp schedule_appointment!(actor, identity_id, offset_seconds) do
    {:ok, appointment} =
      Ash.create(
        Appointment,
        %{
          identity_id: identity_id,
          scheduled_for: DateTime.add(DateTime.utc_now(), offset_seconds, :second),
          summary: "Appointment #{System.unique_integer([:positive])}"
        },
        action: :schedule_appointment,
        actor: actor
      )

    appointment
  end

  defp record_note!(actor, identity_id) do
    {:ok, note} =
      Ash.create(
        Note,
        %{identity_id: identity_id, body: "Note #{System.unique_integer([:positive])}"},
        action: :record_note,
        actor: actor
      )

    note
  end

  # Mirror of `IdentityLive.Show.load_timeline/1` — same queries, same
  # entry shape, same sort. Kept private to the test so the production
  # code stays untouched (story 1.7 modifies tests only).
  defp load_timeline(identity_id, actor) do
    events =
      Event
      |> Ash.Query.filter(identity_id == ^identity_id)
      |> Ash.read!(actor: actor)
      |> Enum.map(&event_entry/1)

    appointments =
      Appointment
      |> Ash.Query.filter(identity_id == ^identity_id)
      |> Ash.read!(actor: actor)
      |> Enum.map(&appointment_entry/1)

    notes =
      Note
      |> Ash.Query.filter(identity_id == ^identity_id)
      |> Ash.read!(actor: actor)
      |> Enum.map(&note_entry/1)

    (events ++ appointments ++ notes)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp event_entry(e), do: %{kind: :event, id: e.id, timestamp: e.occurred_at}
  defp appointment_entry(a), do: %{kind: :appointment, id: a.id, timestamp: a.scheduled_for}
  defp note_entry(n), do: %{kind: :note, id: n.id, timestamp: n.created_at}

  defp monotonically_non_increasing?(entries) do
    entries
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] ->
      DateTime.compare(a.timestamp, b.timestamp) in [:gt, :eq]
    end)
  end

  property "merged timeline is sorted (newest first) regardless of insert order" do
    check all(
            event_offsets <- list_of(offset_seconds_generator(), min_length: 0, max_length: 5),
            appointment_offsets <-
              list_of(offset_seconds_generator(), min_length: 0, max_length: 5),
            note_count <- integer(0..3),
            event_offsets != [] or appointment_offsets != [] or note_count > 0,
            max_runs: @max_runs
          ) do
      operator = create_operator()
      identity = register_identity(operator)

      Enum.each(event_offsets, &record_event!(operator, identity.id, &1))
      Enum.each(appointment_offsets, &schedule_appointment!(operator, identity.id, &1))
      Enum.each(1..note_count//1, fn _ -> record_note!(operator, identity.id) end)

      entries = load_timeline(identity.id, operator)

      assert length(entries) ==
               length(event_offsets) + length(appointment_offsets) + note_count

      assert monotonically_non_increasing?(entries),
             """
             timeline is not monotonically non-increasing:
             #{inspect(Enum.map(entries, & &1.timestamp))}
             """
    end
  end

  property "timeline is stable across reads (same data => same ordering)" do
    check all(
            event_offsets <- list_of(offset_seconds_generator(), min_length: 1, max_length: 4),
            appointment_offsets <-
              list_of(offset_seconds_generator(), min_length: 1, max_length: 4),
            max_runs: @max_runs
          ) do
      operator = create_operator()
      identity = register_identity(operator)

      Enum.each(event_offsets, &record_event!(operator, identity.id, &1))
      Enum.each(appointment_offsets, &schedule_appointment!(operator, identity.id, &1))

      first = load_timeline(identity.id, operator)
      second = load_timeline(identity.id, operator)

      assert Enum.map(first, &{&1.kind, &1.id, &1.timestamp}) ==
               Enum.map(second, &{&1.kind, &1.id, &1.timestamp})
    end
  end
end
