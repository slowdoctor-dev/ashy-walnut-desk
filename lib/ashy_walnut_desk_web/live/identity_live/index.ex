defmodule AshyWalnutDeskWeb.IdentityLive.Index do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Identity.Identity

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, show_archived?: false) |> load_identities()}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    if admin?(socket.assigns.current_user) do
      {:noreply,
       socket
       |> update(:show_archived?, &(!&1))
       |> load_identities()}
    else
      {:noreply, socket}
    end
  end

  defp load_identities(socket) do
    actor = socket.assigns.current_user
    action = if socket.assigns.show_archived?, do: :read_with_archived, else: :read

    identities = Ash.read!(Identity, action: action, actor: actor)
    assign(socket, identities: identities)
  end

  defp admin?(%{role: :admin}), do: true
  defp admin?(_), do: false

  defp can_write?(%{role: role}) when role in [:admin, :operator], do: true
  defp can_write?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl space-y-6 px-6 py-8">
      <.header>
        {gettext("Identities")}
        <:subtitle>{gettext("Customers and clients on the desk.")}</:subtitle>
        <:actions>
          <.link
            :if={can_write?(@current_user)}
            navigate={~p"/identities/new"}
            data-role="new-identity"
            class="rounded bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
          >
            {gettext("New identity")}
          </.link>
        </:actions>
      </.header>

      <div :if={admin?(@current_user)} class="flex items-center gap-2 text-sm text-zinc-600">
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

      <ul id="identities" data-role="identity-list" class="divide-y divide-zinc-100">
        <li
          :for={identity <- @identities}
          id={"identity-#{identity.id}"}
          data-archived={to_string(archived?(identity))}
          class="flex items-center justify-between gap-4 py-3"
        >
          <div class="min-w-0 flex-1">
            <.link
              navigate={~p"/identities/#{identity.id}"}
              class="font-semibold text-zinc-900 hover:text-zinc-700"
            >
              {to_string(identity.display_name)}
            </.link>
            <p class="mt-0.5 text-xs text-zinc-500" data-role="identity-created-at">
              {gettext("Created")} {format_timestamp(identity.created_at)}
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-3">
            <span
              :if={archived?(identity)}
              class="rounded bg-zinc-200 px-2 text-xs uppercase tracking-wide text-zinc-700"
              data-role="archived-badge"
            >
              {gettext("Archived")}
            </span>
            <.link
              navigate={~p"/identities/#{identity.id}"}
              class="text-sm font-medium text-zinc-600 hover:text-zinc-900"
              data-role="identity-view"
            >
              {gettext("View")} <span aria-hidden="true">→</span>
            </.link>
          </div>
        </li>
      </ul>

      <p :if={@identities == []} data-role="empty-state" class="text-sm text-zinc-500">
        {gettext("No identities yet.")}
      </p>
    </div>
    """
  end

  defp archived?(%{deleted_at: nil}), do: false
  defp archived?(_), do: true
end
