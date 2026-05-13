defmodule AshyWalnutDeskWeb.IdentityLive.Edit do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Identity.Identity

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    actor = socket.assigns.current_user

    case Ash.get(Identity, id, actor: actor) do
      {:ok, identity} ->
        form =
          identity
          |> AshPhoenix.Form.for_update(:update_profile, actor: actor)
          |> to_form()

        {:ok, assign(socket, identity: identity, form: form)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Identity not found."))
         |> push_navigate(to: ~p"/identities")}
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
      {:ok, identity} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Identity updated."))
         |> push_navigate(to: ~p"/identities/#{identity.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl space-y-6 px-6 py-8">
      <.header>{gettext("Edit identity")}</.header>

      <.simple_form
        for={@form}
        id="identity-form"
        phx-change="validate"
        phx-submit="save"
        data-role="edit-identity-form"
      >
        <.input field={@form[:display_name]} type="text" label={gettext("Display name")} required />
        <.input field={@form[:notes_summary]} type="textarea" label={gettext("Notes summary")} />

        <:actions>
          <.button type="submit">{gettext("Save")}</.button>
          <.link
            navigate={~p"/identities/#{@identity.id}"}
            class="text-sm text-zinc-600 hover:text-zinc-900"
          >
            {gettext("Cancel")}
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
