defmodule AshyWalnutDesk.Identity.SoftDeletePropertyTest do
  @moduledoc """
  Property-based test for Phase 1 architecture §11: repeated `archive`
  calls on Identity-axis resources are idempotent and preserve the
  soft-delete invariant.

  For any K ≥ 1 invocations of `:archive` on the same record:

    * `deleted_at` is set on the first call and never changes after.
    * The default `read` (which filters `is_nil(deleted_at)`) never
      returns the archived row.
    * The admin-only `:read_with_archived` still returns it.
    * The count of visible rows is monotonically non-increasing as
      archives accumulate (it never *increases* mid-sequence).

  Exercised on all four soft-deletable resources from story 1.2–1.5:
  Identity, Event, Appointment, Note.

  All property iterations within a single test share one
  `Ecto.Adapters.SQL.Sandbox` transaction. The `users_one_admin_idx`
  unique constraint forbids two admin rows in the same transaction, so
  the admin is created once in `setup` and reused; each iteration only
  generates fresh operators and records.
  """

  use AshyWalnutDesk.DataCase, async: false
  use ExUnitProperties

  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note

  require Ash.Query

  @max_runs 25

  setup do
    %{admin: create_user(:admin)}
  end

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{
          email: "#{role}-#{System.unique_integer([:positive])}@example.com",
          role: role
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

  defp record_event!(actor, identity_id) do
    {:ok, event} =
      Ash.create(
        Event,
        %{
          identity_id: identity_id,
          occurred_at: DateTime.utc_now(),
          summary: "Event #{System.unique_integer([:positive])}"
        },
        action: :record_event,
        actor: actor
      )

    event
  end

  defp schedule_appointment!(actor, identity_id) do
    {:ok, appointment} =
      Ash.create(
        Appointment,
        %{
          identity_id: identity_id,
          scheduled_for: DateTime.add(DateTime.utc_now(), 3600, :second),
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

  defp archive!(record, actor) do
    {:ok, archived} = Ash.update(record, %{}, action: :archive, actor: actor)
    archived
  end

  defp visible_count(resource, id, actor) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read!(actor: actor)
    |> length()
  end

  defp visible_count_with_archived(resource, id, actor) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read!(action: :read_with_archived, actor: actor)
    |> length()
  end

  defp total_visible(resource, identity_id, actor) do
    resource
    |> Ash.Query.filter(identity_id == ^identity_id)
    |> Ash.read!(actor: actor)
    |> length()
  end

  defp assert_archive_idempotent(resource, record, archiver, admin) do
    initial_count = visible_count(resource, record.id, admin)

    {archives, visible_counts} =
      Enum.reduce(1..6, {[], record, [initial_count]}, fn _, {acc, prev, counts} ->
        archived = archive!(prev, archiver)
        new_count = visible_count(resource, record.id, admin)
        {acc ++ [archived], archived, counts ++ [new_count]}
      end)
      |> then(fn {acc, _last, counts} -> {acc, counts} end)

    [first | rest] = archives

    refute is_nil(first.deleted_at), "first archive must set deleted_at"

    Enum.each(rest, fn next ->
      assert DateTime.compare(first.deleted_at, next.deleted_at) == :eq,
             "repeat archive must not change deleted_at"
    end)

    assert visible_count(resource, record.id, admin) == 0
    assert visible_count_with_archived(resource, record.id, admin) == 1

    pairs = Enum.chunk_every(visible_counts, 2, 1, :discard)

    assert Enum.all?(pairs, fn [a, b] -> b <= a end),
           """
           visible-row count must be monotonically non-increasing across
           repeated archives, got: #{inspect(visible_counts)}
           """
  end

  property "archive is idempotent on Identity", %{admin: admin} do
    check all(_ <- constant(:_), max_runs: @max_runs) do
      operator = create_user(:operator)
      identity = register_identity(operator)

      assert_archive_idempotent(Identity, identity, operator, admin)
    end
  end

  property "archive is idempotent on Event", %{admin: admin} do
    check all(_ <- constant(:_), max_runs: @max_runs) do
      operator = create_user(:operator)
      identity = register_identity(operator)
      event = record_event!(operator, identity.id)

      assert_archive_idempotent(Event, event, operator, admin)
    end
  end

  property "archive is idempotent on Appointment", %{admin: admin} do
    check all(_ <- constant(:_), max_runs: @max_runs) do
      operator = create_user(:operator)
      identity = register_identity(operator)
      appointment = schedule_appointment!(operator, identity.id)

      assert_archive_idempotent(Appointment, appointment, operator, admin)
    end
  end

  property "archive is idempotent on Note", %{admin: admin} do
    check all(_ <- constant(:_), max_runs: @max_runs) do
      operator = create_user(:operator)
      identity = register_identity(operator)
      note = record_note!(operator, identity.id)

      assert_archive_idempotent(Note, note, operator, admin)
    end
  end

  property "mixed-record archive on an Identity is monotonically non-increasing",
           %{admin: admin} do
    check all(
            event_count <- integer(0..4),
            appointment_count <- integer(0..4),
            note_count <- integer(0..4),
            event_count + appointment_count + note_count > 0,
            max_runs: @max_runs
          ) do
      operator = create_user(:operator)
      identity = register_identity(operator)

      events = for _ <- 1..event_count//1, do: record_event!(operator, identity.id)

      appointments =
        for _ <- 1..appointment_count//1, do: schedule_appointment!(operator, identity.id)

      notes = for _ <- 1..note_count//1, do: record_note!(operator, identity.id)

      assert total_visible(Event, identity.id, admin) == event_count
      assert total_visible(Appointment, identity.id, admin) == appointment_count
      assert total_visible(Note, identity.id, admin) == note_count

      Enum.each(events ++ appointments ++ notes, &archive!(&1, operator))

      assert total_visible(Event, identity.id, admin) == 0
      assert total_visible(Appointment, identity.id, admin) == 0
      assert total_visible(Note, identity.id, admin) == 0

      Enum.each(events ++ appointments ++ notes, fn r ->
        {:ok, _} = Ash.update(r, %{}, action: :archive, actor: operator)
      end)

      assert total_visible(Event, identity.id, admin) == 0
      assert total_visible(Appointment, identity.id, admin) == 0
      assert total_visible(Note, identity.id, admin) == 0
    end
  end
end
