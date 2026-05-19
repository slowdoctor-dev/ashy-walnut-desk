defmodule AshyWalnutDeskWeb.IdentityLive.ShowTest do
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
    email = "identity-show-#{role}-#{System.unique_integer([:positive])}@example.com"

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

    {:ok, _} =
      Ash.update(user, %{role: role}, action: :assign_role, authorize?: false)

    {recycle(conn), Ash.reload!(user, authorize?: false)}
  end

  defp register_identity(actor) do
    Ash.create!(
      Identity,
      %{
        display_name: "Subject #{System.unique_integer([:positive])}",
        primary_identifier: "+1555#{System.unique_integer([:positive])}"
      },
      action: :register_identity,
      actor: actor
    )
  end

  defp record_event(actor, identity, attrs) do
    Ash.create!(
      Event,
      Map.merge(
        %{
          identity_id: identity.id,
          occurred_at: DateTime.utc_now() |> DateTime.add(-3, :hour),
          summary: "Event summary"
        },
        attrs
      ),
      action: :record_event,
      actor: actor
    )
  end

  defp schedule_appointment(actor, identity, attrs) do
    Ash.create!(
      Appointment,
      Map.merge(
        %{
          identity_id: identity.id,
          scheduled_for: DateTime.utc_now() |> DateTime.add(2, :day),
          summary: "Appointment summary"
        },
        attrs
      ),
      action: :schedule_appointment,
      actor: actor
    )
  end

  defp record_note(actor, identity, attrs) do
    Ash.create!(
      Note,
      Map.merge(%{identity_id: identity.id, body: "Note body"}, attrs),
      action: :record_note,
      actor: actor
    )
  end

  # AC1 — Show route renders for authenticated actors

  test "redirects guests to sign-in", %{conn: conn} do
    {seed_conn, operator} = sign_in_as(build_conn(), :operator)
    identity = register_identity(operator)
    _ = seed_conn

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/identities/#{identity.id}")
    assert to =~ "/sign-in"
  end

  test "redirects to index when identity does not exist", %{conn: conn} do
    {conn, _operator} = sign_in_as(conn, :operator)

    missing = Ecto.UUID.generate()

    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/identities/#{missing}")
    assert to =~ "/identities"
  end

  # AC2 — Timeline renders linked Event/Appointment/Note chronologically

  test "timeline shows linked event, appointment, and note in chronological order", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    identity = register_identity(operator)

    event = record_event(operator, identity, %{summary: "Initial visit"})
    appointment = schedule_appointment(operator, identity, %{summary: "Follow-up appointment"})
    note = record_note(operator, identity, %{body: "Internal note text"})

    {:ok, view, html} = live(conn, ~p"/identities/#{identity.id}")

    assert html =~ "Initial visit"
    assert html =~ "Follow-up appointment"
    assert html =~ "Internal note text"

    assert has_element?(view, "#timeline-event-#{event.id}")
    assert has_element?(view, "#timeline-appointment-#{appointment.id}")
    assert has_element?(view, "#timeline-note-#{note.id}")

    timestamps =
      view
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("[data-role=timeline] li")
      |> Enum.map(&Floki.attribute(&1, "data-timestamp"))
      |> List.flatten()

    assert timestamps == Enum.sort(timestamps, :desc)
  end

  test "timeline shows empty state when nothing is linked", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    identity = register_identity(operator)

    {:ok, view, _html} = live(conn, ~p"/identities/#{identity.id}")

    assert has_element?(view, "[data-role=timeline-empty]")
  end

  # AC3 — Viewer sees the timeline; UI hides write affordances; write attempts fail

  test "viewer sees the timeline but no write affordances", %{conn: conn} do
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)
    identity = register_identity(admin)
    record_event(admin, identity, %{summary: "Visible to viewer"})
    _ = admin_conn

    {conn, _viewer} = sign_in_as(conn, :viewer)

    {:ok, view, html} = live(conn, ~p"/identities/#{identity.id}")

    assert html =~ "[redacted]"
    refute has_element?(view, "[data-role=write-actions]")
    refute has_element?(view, "[data-role=edit-identity]")
    refute has_element?(view, "[data-role=archive-identity]")
    refute has_element?(view, "[data-role=recover-identity]")
  end

  test "viewer write attempts fail at the Ash action boundary", %{conn: conn} do
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)
    identity = register_identity(admin)
    _ = admin_conn

    {_conn, viewer} = sign_in_as(conn, :viewer)

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
  end

  # AC2/AC3 — Operator can record an event through the UI

  test "operator records an event through the Show LiveView", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    identity = register_identity(operator)

    {:ok, view, _html} = live(conn, ~p"/identities/#{identity.id}")

    occurred_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()

    html =
      view
      |> form("#event-form", %{
        "event_form" => %{
          "occurred_at" => occurred_at,
          "summary" => "Walked through the UI",
          "body" => ""
        }
      })
      |> render_submit()

    assert html =~ "Walked through the UI"

    events = Event |> Ash.Query.filter(identity_id == ^identity.id) |> Ash.read!(actor: operator)
    assert Enum.any?(events, &(&1.summary == "Walked through the UI"))
  end

  # AC4 — Archive/recover behavior

  test "operator can archive an identity from the Show view", %{conn: conn} do
    {conn, operator} = sign_in_as(conn, :operator)
    identity = register_identity(operator)

    {:ok, view, _html} = live(conn, ~p"/identities/#{identity.id}")
    assert has_element?(view, "[data-role=archive-identity]")
    refute has_element?(view, "[data-role=recover-identity]")

    view |> element("[data-role=archive-identity]") |> render_click()

    refute has_element?(view, "[data-role=archive-identity]")
    refute has_element?(view, "[data-role=write-actions]")

    reloaded =
      Ash.get!(Identity, identity.id, action: :read_with_archived, authorize?: false)

    refute is_nil(reloaded.deleted_at)
    _ = operator
  end

  test "admin can recover an archived identity from the Show view", %{conn: conn} do
    {conn, admin} = sign_in_as(conn, :admin)
    identity = register_identity(admin)
    {:ok, archived} = Ash.update(identity, %{}, action: :archive, actor: admin)

    {:ok, admin_view, html} = live(conn, ~p"/identities/#{archived.id}")
    assert html =~ "Archived"
    assert has_element?(admin_view, "[data-role=archived-banner]")
    assert has_element?(admin_view, "[data-role=recover-identity]")
    refute has_element?(admin_view, "[data-role=archive-identity]")
    refute has_element?(admin_view, "[data-role=write-actions]")

    admin_view |> element("[data-role=recover-identity]") |> render_click()

    refute has_element?(admin_view, "[data-role=recover-identity]")
    reloaded = Ash.get!(Identity, archived.id, actor: admin)
    assert is_nil(reloaded.deleted_at)
  end

  test "operator cannot recover an archived identity", %{conn: conn} do
    {admin_conn, admin} = sign_in_as(build_conn(), :admin)
    identity = register_identity(admin)
    {:ok, archived} = Ash.update(identity, %{}, action: :archive, actor: admin)
    _ = admin_conn

    {_conn, operator} = sign_in_as(conn, :operator)

    assert {:error, %Ash.Error.Forbidden{}} =
             Ash.update(archived, %{}, action: :recover, actor: operator)
  end
end
