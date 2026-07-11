defmodule AshyWalnutDeskWeb.ManualLive.Form do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  require Ash.Query

  alias AshyWalnutDesk.Knowledge.Manual

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case params do
      %{"id" => id} ->
        case Ash.get(Manual, id, action: :read_with_archived, actor: actor) do
          {:ok, manual} ->
            form = manual |> AshPhoenix.Form.for_update(:revise, actor: actor) |> to_form()

            {:ok,
             assign(socket,
               manual: manual,
               form: form,
               mode: :edit,
               versions: load_versions(manual)
             )}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Manual not found."))
             |> push_navigate(to: ~p"/manuals")}
        end

      _ ->
        form = Manual |> AshPhoenix.Form.for_create(:author, actor: actor) |> to_form()
        {:ok, assign(socket, manual: nil, form: form, mode: :new, versions: [])}
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  @impl true
  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _manual} ->
        {:noreply,
         socket
         |> put_flash(:info, success_message(socket.assigns.mode))
         |> push_navigate(to: ~p"/manuals")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp success_message(:new), do: gettext("Manual created; indexing queued.")
  defp success_message(:edit), do: gettext("Manual revised; re-indexing queued.")

  # Paper-trail history, newest first — read with authorize?: false
  # AFTER the admin-only on_mount gate (Manual.Version reads are
  # admin-only by policy; the actor here is already an admin, this
  # just avoids loading version field policies for display).
  defp load_versions(manual) do
    Manual.Version
    |> Ash.Query.filter(version_source_id == ^manual.id)
    |> Ash.Query.sort(version_inserted_at: :desc)
    |> Ash.Query.limit(20)
    |> Ash.read!(authorize?: false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 px-6 py-8">
      <.header>
        <%= if @mode == :new do %>
          {gettext("New manual")}
        <% else %>
          {gettext("Edit manual")}
        <% end %>
        <:subtitle :if={@mode == :edit}>
          {gettext("Revision")} {@manual.revision} · {@manual.slug}
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="manual-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label={gettext("Title")} required />
        <.input
          :if={@mode == :new}
          field={@form[:slug]}
          type="text"
          label={gettext("Slug")}
          required
        />
        <.input field={@form[:body]} type="textarea" label={gettext("Body")} required rows="14" />

        <:actions>
          <.button type="submit">{gettext("Save")}</.button>
          <.link navigate={~p"/manuals"} class="text-sm text-zinc-600 hover:text-zinc-900">
            {gettext("Cancel")}
          </.link>
        </:actions>
      </.simple_form>

      <section :if={@mode == :edit} class="space-y-2" data-role="version-history">
        <h3 class="text-sm font-semibold text-zinc-900">{gettext("Version history")}</h3>

        <p :if={@versions == []} class="text-sm text-zinc-500">
          {gettext("No recorded versions yet.")}
        </p>

        <ul class="divide-y divide-zinc-100">
          <li
            :for={version <- @versions}
            class="py-2 text-sm text-zinc-700"
            data-role="version-row"
          >
            <span class="font-medium">{version.version_action_name}</span>
            · {Calendar.strftime(version.version_inserted_at, "%Y-%m-%d %H:%M")}
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
