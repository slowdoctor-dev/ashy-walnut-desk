defmodule AshyWalnutDeskWeb.PersonaLive.Form do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Knowledge.Persona

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case params do
      %{"id" => id} ->
        case Ash.get(Persona, id, action: :read_with_archived, actor: actor) do
          {:ok, persona} ->
            form = persona |> AshPhoenix.Form.for_update(:update, actor: actor) |> to_form()
            {:ok, assign(socket, persona: persona, form: form, mode: :edit)}

          {:error, _} ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Persona not found."))
             |> push_navigate(to: ~p"/personas")}
        end

      _ ->
        form = Persona |> AshPhoenix.Form.for_create(:create, actor: actor) |> to_form()
        {:ok, assign(socket, persona: nil, form: form, mode: :new)}
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
      {:ok, _persona} ->
        {:noreply,
         socket
         |> put_flash(:info, success_message(socket.assigns.mode))
         |> push_navigate(to: ~p"/personas")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  @impl true
  def handle_event("archive", _params, %{assigns: %{mode: :edit, persona: persona}} = socket) do
    actor = socket.assigns.current_user

    case Ash.update(persona, %{}, action: :archive, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Persona archived."))
         |> push_navigate(to: ~p"/personas")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not archive persona."))}
    end
  end

  def handle_event("archive", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("recover", _params, %{assigns: %{mode: :edit, persona: persona}} = socket) do
    actor = socket.assigns.current_user

    case Ash.update(persona, %{}, action: :recover, actor: actor) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Persona recovered."))
         |> push_navigate(to: ~p"/personas")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not recover persona."))}
    end
  end

  def handle_event("recover", _params, socket), do: {:noreply, socket}

  defp success_message(:new), do: gettext("Persona created.")
  defp success_message(:edit), do: gettext("Persona updated.")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 px-6 py-8">
      <.header>
        <%= if @mode == :new do %>
          {gettext("New persona")}
        <% else %>
          {gettext("Edit persona")}
        <% end %>
      </.header>

      <.simple_form for={@form} id="persona-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label={gettext("Name")} required />
        <.input field={@form[:slug]} type="text" label={gettext("Slug")} required={@mode == :new} />
        <.input
          field={@form[:system_prompt]}
          type="textarea"
          label={gettext("System prompt")}
          required
        />
        <.input
          field={@form[:disclosure_text]}
          type="textarea"
          label={gettext("Disclosure text")}
          required
        />
        <.input
          field={@form[:guardrail_notes]}
          type="textarea"
          label={gettext("Guardrail notes")}
        />
        <.input field={@form[:model_override]} type="text" label={gettext("Model override")} />
        <.input
          field={@form[:status]}
          type="select"
          label={gettext("Status")}
          options={[:active, :archived]}
        />

        <:actions>
          <.button type="submit">{gettext("Save")}</.button>
          <.link navigate={~p"/personas"} class="text-sm text-zinc-600 hover:text-zinc-900">
            {gettext("Cancel")}
          </.link>
        </:actions>
      </.simple_form>

      <div :if={@mode == :edit} class="flex items-center gap-2">
        <button
          :if={@persona.status != :archived}
          type="button"
          phx-click="archive"
          class="rounded border border-zinc-300 px-2 py-1 text-sm hover:bg-zinc-100"
          data-role="archive-persona"
        >
          {gettext("Archive")}
        </button>

        <button
          :if={@persona.status == :archived}
          type="button"
          phx-click="recover"
          class="rounded border border-zinc-300 px-2 py-1 text-sm hover:bg-zinc-100"
          data-role="recover-persona"
        >
          {gettext("Recover")}
        </button>
      </div>
    </div>
    """
  end
end
