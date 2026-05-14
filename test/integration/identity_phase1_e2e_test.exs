defmodule AshyWalnutDesk.Integration.IdentityPhase1E2ETest do
  @moduledoc """
  Phase 1 integration gate (story 1.10).

  Exercises the full Identity-axis composition end-to-end through the
  LiveView and Ash boundaries: create identity → record event → schedule
  follow-up appointment (linked to the originating event) → record note
  → assert the merged timeline renders all three in operator-visible
  order. Then asserts the role boundaries that AC2 calls out — `:viewer`
  is read-only across UI + Ash actions, only `:admin` can recover an
  archived identity.

  This test deliberately stays composition-focused. Per-action policy
  matrices, validations, soft-delete semantics, hashing, and timeline
  ordering invariants are covered by the unit and property tests in
  stories 1.2–1.9.
  """

  use AshyWalnutDeskWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy.MagicLink
  alias AshyWalnutDesk.Accounts.User
  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note

  require Ash.Query

  defp sign_in_as(conn, role) do
    email = "phase-1-e2e-#{role}-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Ash.create(
        User,
        %{email: email, role: role},
        action: :register,
        authorize?: false
      )

    strategy = Info.strategy!(User, :magic_link)
    {:ok, token} = MagicLink.request_token_for_identity(strategy, email)
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => token}})

    # `:sign_in_with_magic_link` runs `AssignFirstUserAdmin`, which may
    # override the role we asked for. Restore it after sign-in so the
    # LiveView observes the test-intended role.
    {:ok, _} =
      Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)

    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp create_user(role) do
    {:ok, user} =
      Ash.create(
        User,
        %{
          email: "phase-1-e2e-#{role}-#{System.unique_integer([:positive])}@example.com",
          role: role
        },
        action: :register,
        authorize?: false
      )

    user
  end

  # AC1 — Phase 1 composition: create → link → timeline.

  test "operator drives create identity → event → follow-up appointment → note → timeline renders chronologically",
       %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)

    # Create the identity via IdentityLive.New, follow the redirect onto
    # IdentityLive.Show (where the linked-record forms live).
    {:ok, new_view, _html} = live(conn, ~p"/identities/new")

    {:ok, show_view, _html} =
      new_view
      |> form("#identity-form", %{
        "form" => %{
          "display_name" => "Integration Subject",
          "primary_identifier" => "+15550000001"
        }
      })
      |> render_submit()
      |> follow_redirect(conn)

    identity =
      Identity
      |> Ash.Query.filter(display_name == "Integration Subject")
      |> Ash.read_one!(actor: operator)

    refute is_nil(identity), "identity was not created via the LiveView form"

    # Record the originating event via the Show LV inline form.
    occurred_at =
      DateTime.utc_now()
      |> DateTime.add(-3, :hour)
      |> DateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()

    show_view
    |> form("#event-form", %{
      "event_form" => %{
        "occurred_at" => occurred_at,
        "summary" => "Initial encounter recorded",
        "body" => ""
      }
    })
    |> render_submit()

    event =
      Event
      |> Ash.Query.filter(identity_id == ^identity.id)
      |> Ash.read_one!(actor: operator)

    refute is_nil(event), "event was not created via the Show form"

    # Schedule a follow-up appointment linked to the originating event.
    # The Show LV's `appointment_form` doesn't expose
    # `originating_event_id` (Phase 1 architecture defers a full
    # follow-up linker UI to a later phase), so the link is exercised
    # through the same `:schedule_appointment` action the LV would call.
    {:ok, appointment} =
      Ash.create(
        Appointment,
        %{
          identity_id: identity.id,
          scheduled_for: DateTime.utc_now() |> DateTime.add(2, :day),
          summary: "Follow-up consultation",
          appointment_type: :follow_up,
          originating_event_id: event.id
        },
        action: :schedule_appointment,
        actor: operator
      )

    assert appointment.appointment_type == :follow_up
    assert appointment.originating_event_id == event.id

    # Record the operator note via the Show LV inline form.
    show_view
    |> form("#note-form", %{
      "note_form" => %{"body" => "Operator observation"}
    })
    |> render_submit()

    note =
      Note
      |> Ash.Query.filter(identity_id == ^identity.id)
      |> Ash.read_one!(actor: operator)

    refute is_nil(note), "note was not created via the Show form"

    # Re-mount Show so the timeline reflects all three linked records.
    {:ok, view, html} = live(conn, ~p"/identities/#{identity.id}")

    assert html =~ "Initial encounter recorded"
    assert html =~ "Follow-up consultation"
    assert html =~ "Operator observation"

    assert has_element?(view, "#timeline-event-#{event.id}")
    assert has_element?(view, "#timeline-appointment-#{appointment.id}")
    assert has_element?(view, "#timeline-note-#{note.id}")

    timeline_items =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("[data-role=timeline] li")

    timestamps =
      timeline_items
      |> Enum.map(&Floki.attribute(&1, "data-timestamp"))
      |> List.flatten()

    assert timestamps == Enum.sort(timestamps, :desc),
           "timeline must render newest-first; got #{inspect(timestamps)}"

    ids =
      timeline_items
      |> Enum.map(&Floki.attribute(&1, "id"))
      |> List.flatten()

    assert ids == [
             "timeline-appointment-#{appointment.id}",
             "timeline-note-#{note.id}",
             "timeline-event-#{event.id}"
           ],
           "expected appointment (future) → note (now) → event (past); got #{inspect(ids)}"
  end

  # AC2 — Role boundaries: viewer read-only; only admin recovers.

  test "viewer reads the timeline but cannot write; only admin can recover an archived identity",
       %{conn: conn} do
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)

    {:ok, identity} =
      Ash.create(
        Identity,
        %{
          display_name: "Boundary Subject",
          primary_identifier: "+15550000002"
        },
        action: :register_identity,
        actor: admin
      )

    {:ok, _seed_event} =
      Ash.create(
        Event,
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          summary: "Recorded by admin"
        },
        action: :record_event,
        actor: admin
      )

    # Viewer mounts Show: sees the timeline, has no write affordances.
    {viewer_conn, viewer} = sign_in_as(conn, :viewer)

    {:ok, viewer_view, html} = live(viewer_conn, ~p"/identities/#{identity.id}")

    assert html =~ "Recorded by admin"
    refute has_element?(viewer_view, "[data-role=write-actions]")
    refute has_element?(viewer_view, "[data-role=edit-identity]")
    refute has_element?(viewer_view, "[data-role=archive-identity]")
    refute has_element?(viewer_view, "[data-role=recover-identity]")

    # Viewer write attempts at the Ash boundary are forbidden.
    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(
               Event,
               %{
                 identity_id: identity.id,
                 occurred_at: DateTime.utc_now(),
                 summary: "Viewer tried"
               },
               action: :record_event,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.create(
               Note,
               %{identity_id: identity.id, body: "Viewer tried"},
               action: :record_note,
               actor: viewer
             )

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(identity, %{}, action: :archive, actor: viewer)

    # Operator can archive but cannot recover.
    operator = create_user(:operator)

    {:ok, archived} = Ash.update(identity, %{}, action: :archive, actor: operator)
    refute is_nil(archived.deleted_at)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)

    # Admin drives recovery through the Show LV (the operator-facing
    # path) and the identity is restored.
    {:ok, admin_view, admin_html} = live(admin_conn, ~p"/identities/#{archived.id}")

    assert admin_html =~ "Archived"
    assert has_element?(admin_view, "[data-role=archived-banner]")
    assert has_element?(admin_view, "[data-role=recover-identity]")
    refute has_element?(admin_view, "[data-role=archive-identity]")

    admin_view |> element("[data-role=recover-identity]") |> render_click()

    reloaded = Ash.get!(Identity, archived.id, actor: admin)
    assert is_nil(reloaded.deleted_at)
  end
end
