defmodule AshyWalnutDeskWeb.IdentityLive.New do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Identity.Identity

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user

    form =
      Identity
      |> AshPhoenix.Form.for_create(:register_identity, actor: actor)
      |> to_form()

    {:ok, assign(socket, form: form)}
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
         |> put_flash(:info, gettext("Identity registered."))
         |> push_navigate(to: ~p"/identities/#{identity.id}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl space-y-6 px-6 py-8">
      <.header>{gettext("New identity")}</.header>

      <.simple_form
        for={@form}
        id="identity-form"
        phx-change="validate"
        phx-submit="save"
        data-role="new-identity-form"
      >
        <.input field={@form[:display_name]} type="text" label={gettext("Display name")} required />
        <.input
          field={@form[:primary_identifier]}
          type="text"
          label={gettext("Primary identifier")}
          required
        />
        <.input field={@form[:notes_summary]} type="textarea" label={gettext("Notes summary")} />

        <:actions>
          <.button type="submit">{gettext("Register identity")}</.button>
          <.link navigate={~p"/identities"} class="text-sm text-zinc-600 hover:text-zinc-900">
            {gettext("Cancel")}
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
