defmodule AshyWalnutDeskWeb.PersonaLive.Index do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Knowledge.Persona

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, show_archived?: false) |> load_personas()}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    {:noreply, socket |> update(:show_archived?, &(!&1)) |> load_personas()}
  end

  defp load_personas(socket) do
    actor = socket.assigns.current_user
    action = if socket.assigns.show_archived?, do: :read_with_archived, else: :read
    personas = Ash.read!(Persona, action: action, actor: actor)
    assign(socket, personas: personas)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6 px-6 py-8">
      <.header>
        {gettext("Personas")}
        <:subtitle>{gettext("Deployment tone and policy profile definitions.")}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/personas/new"}
            class="rounded bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
            data-role="new-persona"
          >
            {gettext("New persona")}
          </.link>
        </:actions>
      </.header>

      <div class="flex items-center gap-2 text-sm text-zinc-600">
        <button
          type="button"
          phx-click="toggle_archived"
          data-role="toggle-archived"
          class="rounded border border-zinc-300 px-2 py-1 hover:bg-zinc-100"
        >
          <%= if @show_archived? do %>
            {gettext("Hide archived")}
          <% else %>
            {gettext("Show archived")}
          <% end %>
        </button>
      </div>

      <ul id="personas" data-role="persona-list" class="divide-y divide-zinc-100">
        <li :for={persona <- @personas} id={"persona-#{persona.id}"} class="py-3">
          <div class="flex items-center justify-between gap-4">
            <div class="min-w-0 flex-1">
              <p class="font-semibold text-zinc-900">{persona.name}</p>
              <p class="text-xs text-zinc-500">{persona.slug}</p>
            </div>
            <div class="flex items-center gap-3">
              <span
                :if={persona.status == :archived}
                class="rounded bg-zinc-200 px-2 text-xs uppercase tracking-wide text-zinc-700"
                data-role="archived-badge"
              >
                {gettext("Archived")}
              </span>
              <.link
                navigate={~p"/personas/#{persona.id}/edit"}
                class="text-sm font-medium text-zinc-600 hover:text-zinc-900"
                data-role="edit-persona"
              >
                {gettext("Edit")} <span aria-hidden="true">→</span>
              </.link>
            </div>
          </div>
        </li>
      </ul>

      <p :if={@personas == []} data-role="empty-state" class="text-sm text-zinc-500">
        {gettext("No personas yet.")}
      </p>
    </div>
    """
  end
end
