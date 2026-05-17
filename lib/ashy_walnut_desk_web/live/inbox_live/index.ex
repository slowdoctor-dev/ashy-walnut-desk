defmodule AshyWalnutDeskWeb.InboxLive.Index do
  @moduledoc false

  use AshyWalnutDeskWeb, :live_view

  alias AshyWalnutDesk.Interaction.Inbox
  require Ash.Query

  on_mount {AshyWalnutDeskWeb.LiveUserAuth, :live_user_required}

  @statuses ~w(open drafting executed dismissed)

  @impl true
  def mount(params, _session, socket) do
    status = normalize_status(Map.get(params, "status"))

    {:ok,
     socket
     |> assign(status_filter: status, show_archived?: false, statuses: @statuses)
     |> load_inboxes()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = normalize_status(Map.get(params, "status"))
    {:noreply, socket |> assign(status_filter: status) |> load_inboxes()}
  end

  @impl true
  def handle_event("toggle_archived", _params, socket) do
    if admin?(socket.assigns.current_user) do
      {:noreply, socket |> update(:show_archived?, &(!&1)) |> load_inboxes()}
    else
      {:noreply, socket}
    end
  end

  defp load_inboxes(socket) do
    actor = socket.assigns.current_user
    action = if socket.assigns.show_archived?, do: :read_with_archived, else: :read

    inboxes =
      Inbox
      |> Ash.Query.for_read(action, %{}, actor: actor)
      |> Ash.Query.filter(status == ^String.to_existing_atom(socket.assigns.status_filter))
      |> Ash.Query.sort(created_at: :desc)
      |> Ash.Query.load(conversation: :identity)
      |> Ash.read!()

    assign(socket, inboxes: inboxes)
  end

  defp normalize_status(status) when status in @statuses, do: status
  defp normalize_status(_), do: "open"

  defp admin?(%{role: :admin}), do: true
  defp admin?(_), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl space-y-6 px-6 py-8">
      <.header>
        {gettext("Inbox")}
        <:subtitle>{gettext("Operator queue from inbox to action.")}</:subtitle>
        <:actions>
          <.link
            navigate={~p"/inbox/new"}
            class="rounded border border-zinc-300 px-3 py-2 text-sm hover:bg-zinc-100"
          >
            {gettext("New inbox")}
          </.link>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center gap-2">
        <.link
          :for={status <- @statuses}
          patch={~p"/inbox?status=#{status}"}
          class="rounded border px-2 py-1 text-xs uppercase tracking-wide"
        >
          {status}
        </.link>
      </div>

      <button
        :if={admin?(@current_user)}
        type="button"
        phx-click="toggle_archived"
        data-role="toggle-archived"
        class="rounded border border-zinc-300 px-2 py-1 text-sm hover:bg-zinc-100"
      >
        {if @show_archived?, do: gettext("Hide archived"), else: gettext("Show archived")}
      </button>

      <ul class="divide-y divide-zinc-100" data-role="inbox-list">
        <li
          :for={inbox <- @inboxes}
          id={"inbox-#{inbox.id}"}
          class="flex items-center justify-between gap-4 py-3"
        >
          <div class="min-w-0 flex-1">
            <p class="text-xs uppercase tracking-wide text-zinc-500">{to_string(inbox.status)}</p>
            <p class="truncate text-sm text-zinc-900">{inbox.summary}</p>
            <p class="text-xs text-zinc-500">{inbox.conversation.identity.display_name}</p>
          </div>
          <.link
            navigate={~p"/inbox/#{inbox.id}"}
            class="text-sm font-medium text-zinc-700 hover:text-zinc-900"
            data-role="inbox-view"
          >
            {gettext("View")} <span aria-hidden="true">→</span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
