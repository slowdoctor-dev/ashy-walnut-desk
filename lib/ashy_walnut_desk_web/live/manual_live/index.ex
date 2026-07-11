defmodule AshyWalnutDeskWeb.ManualLive.Index do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Knowledge.Manual

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :load_from_cookie}
  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, show_archived?: false) |> load_manuals()}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    {:noreply, socket |> update(:show_archived?, &(!&1)) |> load_manuals()}
  end

  @impl true
  def handle_event("archive", %{"id" => id}, socket) do
    flip_status(socket, id, :archive, gettext("Manual archived."))
  end

  @impl true
  def handle_event("restore", %{"id" => id}, socket) do
    flip_status(socket, id, :restore, gettext("Manual restored."))
  end

  defp flip_status(socket, id, action, success_message) do
    actor = socket.assigns.current_user

    with {:ok, manual} <- Ash.get(Manual, id, action: :read_with_archived, actor: actor),
         {:ok, _} <- Ash.update(manual, %{}, action: action, actor: actor) do
      {:noreply, socket |> put_flash(:info, success_message) |> load_manuals()}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update manual."))}
    end
  end

  defp load_manuals(socket) do
    actor = socket.assigns.current_user
    action = if socket.assigns.show_archived?, do: :read_with_archived, else: :read
    manuals = Ash.read!(Manual, action: action, actor: actor)
    assign(socket, manuals: manuals)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6 px-6 py-8">
      <.header>
        {gettext("Manuals")}
        <:subtitle>
          {gettext("Deployment knowledge that grounds AI draft generation.")}
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/manuals/new"}
            class="rounded bg-zinc-900 px-3 py-2 text-sm font-semibold text-white hover:bg-zinc-700"
            data-role="new-manual"
          >
            {gettext("New manual")}
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

      <ul id="manuals" data-role="manual-list" class="divide-y divide-zinc-100">
        <li :for={manual <- @manuals} id={"manual-#{manual.id}"} class="py-3">
          <div class="flex items-center justify-between gap-4">
            <div class="min-w-0 flex-1">
              <p class="font-semibold text-zinc-900">{manual.title}</p>
              <p class="text-xs text-zinc-500">
                {manual.slug} · {gettext("revision")} {manual.revision}
              </p>
            </div>
            <div class="flex items-center gap-3">
              <span
                :if={manual.status == :archived}
                class="rounded bg-zinc-200 px-2 text-xs uppercase tracking-wide text-zinc-700"
                data-role="archived-badge"
              >
                {gettext("Archived")}
              </span>

              <button
                :if={manual.status == :active}
                type="button"
                phx-click="archive"
                phx-value-id={manual.id}
                class="text-sm font-medium text-zinc-600 hover:text-zinc-900"
                data-role={"archive-manual-#{manual.id}"}
              >
                {gettext("Archive")}
              </button>

              <button
                :if={manual.status == :archived}
                type="button"
                phx-click="restore"
                phx-value-id={manual.id}
                class="text-sm font-medium text-zinc-600 hover:text-zinc-900"
                data-role={"restore-manual-#{manual.id}"}
              >
                {gettext("Restore")}
              </button>

              <.link
                navigate={~p"/manuals/#{manual.id}/edit"}
                class="text-sm font-medium text-zinc-600 hover:text-zinc-900"
                data-role="edit-manual"
              >
                {gettext("Edit")} <span aria-hidden="true">→</span>
              </.link>
            </div>
          </div>
        </li>
      </ul>

      <p :if={@manuals == []} data-role="empty-state" class="text-sm text-zinc-500">
        {gettext("No manuals yet.")}
      </p>
    </div>
    """
  end
end
