defmodule AshyWalnutDeskWeb.IdentityLive.Show do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Identity.Appointment
  alias AshyWalnutDesk.Identity.Event
  alias AshyWalnutDesk.Identity.Identity
  alias AshyWalnutDesk.Identity.Note
  alias AshyWalnutDeskWeb.IdentityLive.TimelineComponent
  require Ash.Query

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case fetch_identity(id, actor) do
      {:ok, identity} ->
        {:ok,
         socket
         |> assign(identity: identity)
         |> assign_forms()
         |> load_timeline()}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Identity not found."))
         |> push_navigate(to: ~p"/identities")}
    end
  end

  defp fetch_identity(id, actor) do
    case Ash.get(Identity, id, actor: actor) do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        if admin?(actor) do
          Ash.get(Identity, id, action: :read_with_archived, actor: actor)
        else
          err
        end
    end
  end

  @impl true
  def handle_event("validate_event", %{"event_form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.event_form, params)
    {:noreply, assign(socket, event_form: form)}
  end

  @impl true
  def handle_event("record_event", %{"event_form" => params}, socket) do
    params = Map.put(params, "identity_id", socket.assigns.identity.id)

    case AshPhoenix.Form.submit(socket.assigns.event_form, params: params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Event recorded."))
         |> assign_forms()
         |> load_timeline()}

      {:error, form} ->
        {:noreply, assign(socket, event_form: form)}
    end
  end

  @impl true
  def handle_event("validate_appointment", %{"appointment_form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.appointment_form, params)
    {:noreply, assign(socket, appointment_form: form)}
  end

  @impl true
  def handle_event("schedule_appointment", %{"appointment_form" => params}, socket) do
    params = Map.put(params, "identity_id", socket.assigns.identity.id)

    case AshPhoenix.Form.submit(socket.assigns.appointment_form, params: params) do
      {:ok, _appointment} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Appointment scheduled."))
         |> assign_forms()
         |> load_timeline()}

      {:error, form} ->
        {:noreply, assign(socket, appointment_form: form)}
    end
  end

  @impl true
  def handle_event("validate_note", %{"note_form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.note_form, params)
    {:noreply, assign(socket, note_form: form)}
  end

  @impl true
  def handle_event("record_note", %{"note_form" => params}, socket) do
    params = Map.put(params, "identity_id", socket.assigns.identity.id)

    case AshPhoenix.Form.submit(socket.assigns.note_form, params: params) do
      {:ok, _note} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Note recorded."))
         |> assign_forms()
         |> load_timeline()}

      {:error, form} ->
        {:noreply, assign(socket, note_form: form)}
    end
  end

  @impl true
  def handle_event("archive_identity", _params, socket) do
    actor = socket.assigns.current_user

    case Ash.update(socket.assigns.identity, %{}, action: :archive, actor: actor) do
      {:ok, identity} ->
        {:noreply,
         socket
         |> assign(identity: identity)
         |> assign_forms()
         |> put_flash(:info, gettext("Identity archived."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not archive identity."))}
    end
  end

  @impl true
  def handle_event("recover_identity", _params, socket) do
    actor = socket.assigns.current_user

    case Ash.update(socket.assigns.identity, %{}, action: :recover, actor: actor) do
      {:ok, identity} ->
        {:noreply,
         socket
         |> assign(identity: identity)
         |> assign_forms()
         |> put_flash(:info, gettext("Identity recovered."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not recover identity."))}
    end
  end

  defp assign_forms(socket) do
    actor = socket.assigns.current_user
    identity = socket.assigns.identity

    if can_write?(actor) and not archived?(identity) do
      event_form =
        Event
        |> AshPhoenix.Form.for_create(:record_event,
          actor: actor,
          as: "event_form",
          params: %{"identity_id" => identity.id}
        )
        |> to_form()

      appointment_form =
        Appointment
        |> AshPhoenix.Form.for_create(:schedule_appointment,
          actor: actor,
          as: "appointment_form",
          params: %{"identity_id" => identity.id}
        )
        |> to_form()

      note_form =
        Note
        |> AshPhoenix.Form.for_create(:record_note,
          actor: actor,
          as: "note_form",
          params: %{"identity_id" => identity.id}
        )
        |> to_form()

      assign(socket,
        event_form: event_form,
        appointment_form: appointment_form,
        note_form: note_form
      )
    else
      assign(socket, event_form: nil, appointment_form: nil, note_form: nil)
    end
  end

  defp load_timeline(socket) do
    actor = socket.assigns.current_user
    identity_id = socket.assigns.identity.id

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

    entries =
      (events ++ appointments ++ notes)
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

    assign(socket, timeline_entries: entries)
  end

  defp event_entry(%Event{} = e) do
    %{
      kind: :event,
      id: e.id,
      timestamp: e.occurred_at,
      summary: e.summary,
      detail: e.body
    }
  end

  defp appointment_entry(%Appointment{} = a) do
    %{
      kind: :appointment,
      id: a.id,
      timestamp: a.scheduled_for,
      summary: a.summary,
      detail: "#{a.appointment_type} · #{a.status}"
    }
  end

  defp note_entry(%Note{} = n) do
    %{
      kind: :note,
      id: n.id,
      timestamp: n.created_at,
      summary: n.body,
      detail: nil
    }
  end

  defp admin?(%{role: :admin}), do: true
  defp admin?(_), do: false

  defp can_write?(%{role: role}) when role in [:admin, :operator], do: true
  defp can_write?(_), do: false

  defp archived?(%{deleted_at: nil}), do: false
  defp archived?(_), do: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-8 px-6 py-8">
      <.header>
        {to_string(@identity.display_name)}
        <:subtitle :if={archived?(@identity)}>
          <span data-role="archived-banner">{gettext("Archived")}</span>
        </:subtitle>
        <:actions>
          <.link
            :if={can_write?(@current_user) and not archived?(@identity)}
            navigate={~p"/identities/#{@identity.id}/edit"}
            data-role="edit-identity"
            class="rounded border border-zinc-300 px-3 py-2 text-sm font-semibold hover:bg-zinc-100"
          >
            {gettext("Edit")}
          </.link>
          <button
            :if={can_write?(@current_user) and not archived?(@identity)}
            type="button"
            phx-click="archive_identity"
            data-role="archive-identity"
            data-confirm={gettext("Archive this identity?")}
            class="rounded border border-zinc-300 px-3 py-2 text-sm font-semibold hover:bg-zinc-100"
          >
            {gettext("Archive")}
          </button>
          <button
            :if={admin?(@current_user) and archived?(@identity)}
            type="button"
            phx-click="recover_identity"
            data-role="recover-identity"
            class="rounded border border-zinc-300 px-3 py-2 text-sm font-semibold hover:bg-zinc-100"
          >
            {gettext("Recover")}
          </button>
        </:actions>
      </.header>

      <.live_component
        module={TimelineComponent}
        id="identity-timeline"
        entries={@timeline_entries}
      />

      <section
        :if={can_write?(@current_user) and not archived?(@identity)}
        class="space-y-6"
        data-role="write-actions"
      >
        <details class="rounded border border-zinc-200 p-4" data-role="record-event-section">
          <summary class="cursor-pointer text-sm font-semibold text-zinc-800">
            {gettext("Record event")}
          </summary>
          <.simple_form
            for={@event_form}
            id="event-form"
            phx-change="validate_event"
            phx-submit="record_event"
          >
            <.input
              field={@event_form[:occurred_at]}
              type="datetime-local"
              label={gettext("Occurred at")}
              required
            />
            <.input field={@event_form[:summary]} type="text" label={gettext("Summary")} required />
            <.input field={@event_form[:body]} type="textarea" label={gettext("Body")} />
            <:actions>
              <.button type="submit">{gettext("Record event")}</.button>
            </:actions>
          </.simple_form>
        </details>

        <details class="rounded border border-zinc-200 p-4" data-role="schedule-appointment-section">
          <summary class="cursor-pointer text-sm font-semibold text-zinc-800">
            {gettext("Schedule appointment")}
          </summary>
          <.simple_form
            for={@appointment_form}
            id="appointment-form"
            phx-change="validate_appointment"
            phx-submit="schedule_appointment"
          >
            <.input
              field={@appointment_form[:scheduled_for]}
              type="datetime-local"
              label={gettext("Scheduled for")}
              required
            />
            <.input
              field={@appointment_form[:summary]}
              type="text"
              label={gettext("Summary")}
              required
            />
            <.input
              field={@appointment_form[:appointment_type]}
              type="select"
              label={gettext("Type")}
              options={[
                {gettext("Initial"), "initial"},
                {gettext("Follow up"), "follow_up"},
                {gettext("Recurring"), "recurring"}
              ]}
            />
            <:actions>
              <.button type="submit">{gettext("Schedule")}</.button>
            </:actions>
          </.simple_form>
        </details>

        <details class="rounded border border-zinc-200 p-4" data-role="record-note-section">
          <summary class="cursor-pointer text-sm font-semibold text-zinc-800">
            {gettext("Record note")}
          </summary>
          <.simple_form
            for={@note_form}
            id="note-form"
            phx-change="validate_note"
            phx-submit="record_note"
          >
            <.input field={@note_form[:body]} type="textarea" label={gettext("Body")} required />
            <:actions>
              <.button type="submit">{gettext("Record note")}</.button>
            </:actions>
          </.simple_form>
        </details>
      </section>

      <.back navigate={~p"/identities"}>{gettext("Back to identities")}</.back>
    </div>
    """
  end
end
